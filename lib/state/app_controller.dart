import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/models.dart';
import '../data/repository.dart';
import '../data/live_repository.dart';
import '../data/demo_repository.dart';

class AppController extends ChangeNotifier with WidgetsBindingObserver {
  final SharedPreferences? preferences;
  final WaiterRepository Function(ConnectionConfig) repositoryFactory;
  ConnectionConfig config;
  WaiterRepository? repository;
  Staff? user;
  FloorSnapshot snapshot = FloorSnapshot([], [], []);
  List<Dish> dishes = [];
  final Map<String, List<CartLine>> drafts = {};
  final Map<String, String?> _draftOrderIds = {};
  final Set<String> uncertainTables = {};
  final Map<String, DateTime> uncertainSince = {};
  final Set<String> staleDraftTables = {};
  Timer? _timer;
  bool busy = false, loading = false, offline = false, _refreshing = false;
  String? error;
  DateTime? lastSync;
  bool get demo => repository?.isDemo == true;
  bool get configured => config.server.isNotEmpty;
  AppController(
      {this.preferences,
      ConnectionConfig? config,
      WaiterRepository Function(ConnectionConfig)? repositoryFactory})
      : repositoryFactory =
            repositoryFactory ?? ((value) => LiveRepository(value)),
        config = config ??
            const ConnectionConfig(
                server: String.fromEnvironment('API_BASE_URL')) {
    WidgetsBinding.instance.addObserver(this);
  }
  Future<void> initialize() async {
    final saved = preferences?.getString('connection');
    if (saved != null) {
      try {
        config = ConnectionConfig.fromJson(jsonDecode(saved));
      } catch (_) {}
    }
    if (!configured) return;
    repository = repositoryFactory(config);
    loading = true;
    notifyListeners();
    try {
      user = await repository!.restore();
      if (user != null) {
        _restoreUncertain();
        await refresh();
        await _restoreDrafts();
        _startTimer();
      }
    } catch (e) {
      error = e.toString();
    }
    loading = false;
    notifyListeners();
  }

  Future<void> saveConfig(ConnectionConfig value) async {
    config = value;
    await preferences?.setString('connection', jsonEncode(value.toJson()));
    repository?.dispose();
    repository = null;
    notifyListeners();
  }

  Future<void> signIn(String identifier, String password) async {
    busy = true;
    error = null;
    notifyListeners();
    try {
      repository?.dispose();
      repository = repositoryFactory(config);
      user = await repository!.login(identifier, password);
      _restoreUncertain();
      await refresh();
      await _restoreDrafts();
      _startTimer();
    } catch (e) {
      error = e.toString();
      rethrow;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> practice() async {
    repository?.dispose();
    repository = DemoRepository();
    user = DemoRepository.staff;
    error = null;
    uncertainTables.clear();
    uncertainSince.clear();
    staleDraftTables.clear();
    await refresh();
    _startTimer();
  }

  String get _pendingKey => 'pending:${config.server}:${user?.id}';
  String get _pendingMetaKey => 'pending-meta:${config.server}:${user?.id}';
  String get _draftKey => 'drafts:${config.server}:${user?.id}';
  void _restoreUncertain() {
    uncertainTables
      ..clear()
      ..addAll(preferences?.getStringList(_pendingKey) ?? []);
    uncertainSince.clear();
    final raw = preferences?.getString(_pendingMetaKey);
    if (raw != null) {
      try {
        final values = Json.from(jsonDecode(raw));
        for (final entry in values.entries) {
          final time = DateTime.tryParse('${entry.value}');
          if (time != null && uncertainTables.contains(entry.key)) {
            uncertainSince[entry.key] = time;
          }
        }
      } catch (_) {}
    }
    final restoredAt = DateTime.now();
    for (final tableId in uncertainTables) {
      uncertainSince.putIfAbsent(tableId, () => restoredAt);
    }
  }

  Future<void> _saveUncertain() async {
    if (!demo) {
      await preferences?.setStringList(_pendingKey, uncertainTables.toList());
      await preferences?.setString(
          _pendingMetaKey,
          jsonEncode({
            for (final id in uncertainTables)
              id: uncertainSince[id]?.toIso8601String()
          }));
    }
  }

  Future<void> _saveDrafts() async {
    if (demo || user == null) return;
    final value = <String, dynamic>{};
    for (final entry in drafts.entries) {
      if (entry.value.isEmpty) continue;
      value[entry.key] = {
        'orderId': _draftOrderIds[entry.key],
        'lines': entry.value
            .map((line) => {
                  'dishId': line.dish.id,
                  'batchId': line.batch?.id,
                  'quantity': line.quantity,
                  'price': line.price,
                })
            .toList()
      };
    }
    if (value.isEmpty) {
      await preferences?.remove(_draftKey);
    } else {
      await preferences?.setString(_draftKey, jsonEncode(value));
    }
  }

  Future<void> _restoreDrafts() async {
    if (demo || user == null) return;
    final raw = preferences?.getString(_draftKey);
    if (raw == null) return;
    drafts.clear();
    _draftOrderIds.clear();
    try {
      final stored = Json.from(jsonDecode(raw));
      for (final entry in stored.entries) {
        final tableId = entry.key;
        final value = Json.from(entry.value);
        final expectedOrderId = value['orderId']?.toString();
        final currentOrderId = snapshot.orderFor(tableId)?.id;
        final tableExists = snapshot.tables.any((table) => table.id == tableId);
        if (!tableExists || expectedOrderId != currentOrderId) {
          staleDraftTables.add(tableId);
          continue;
        }
        final restored = <CartLine>[];
        var valid = true;
        for (final rawLine in (value['lines'] as List? ?? const [])) {
          final saved = Json.from(rawLine);
          final dish = dishes
              .where((item) => item.id == '${saved['dishId']}')
              .firstOrNull;
          if (dish == null) {
            valid = false;
            break;
          }
          final batchId = saved['batchId']?.toString();
          final batch = batchId == null
              ? null
              : dish.batches.where((item) => item.id == batchId).firstOrNull;
          final quantity = number(saved['quantity']).toInt();
          final price = number(saved['price']);
          final livePrice = batch?.price ?? dish.price;
          final limit = batch?.quantity ?? dish.available;
          if ((dish.needsBatch && batch == null) ||
              quantity < 1 ||
              quantity > limit ||
              (livePrice - price).abs() > .001) {
            valid = false;
            break;
          }
          restored.add(CartLine(dish, batch: batch, quantity: quantity));
        }
        if (!valid || !_hasValidSharedStock(restored)) {
          staleDraftTables.add(tableId);
          continue;
        }
        if (restored.isNotEmpty) {
          drafts[tableId] = restored;
          _draftOrderIds[tableId] = expectedOrderId;
        }
      }
    } catch (_) {
      drafts.clear();
      _draftOrderIds.clear();
    }
    await _saveDrafts();
    notifyListeners();
  }

  bool _hasValidSharedStock(List<CartLine> lines) {
    final demand = <String, int>{};
    final limits = <String, int>{};
    for (final line in lines.where((line) => line.batch != null)) {
      final key = '${line.dish.inventoryId}:${line.batch!.id}';
      demand[key] = (demand[key] ?? 0) + line.quantity;
      limits[key] = line.batch!.quantity;
    }
    return demand.entries.every((entry) => entry.value <= limits[entry.key]!);
  }

  Future<void> signOut() async {
    _timer?.cancel();
    final old = repository;
    final oldDraftKey = _draftKey;
    await preferences?.remove(oldDraftKey);
    user = null;
    drafts.clear();
    _draftOrderIds.clear();
    dishes = [];
    snapshot = FloorSnapshot([], [], []);
    uncertainTables.clear();
    uncertainSince.clear();
    staleDraftTables.clear();
    error = null;
    lastSync = null;
    notifyListeners();
    try {
      await old?.logout();
    } finally {
      old?.dispose();
      if (repository == old) repository = null;
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(
        const Duration(seconds: 5), (_) => refresh(silent: true));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && user != null) {
      refresh(silent: true);
      _startTimer();
    } else if (state != AppLifecycleState.resumed) {
      _timer?.cancel();
    }
  }

  Future<void> refresh({bool silent = false, bool reloadMenu = false}) async {
    if (_refreshing || user == null || repository == null) return;
    _refreshing = true;
    final activeRepo = repository!;
    if (!silent) {
      loading = true;
      notifyListeners();
    }
    try {
      final next = await activeRepo.floor();
      final menu =
          dishes.isEmpty || reloadMenu ? await activeRepo.menu() : dishes;
      if (activeRepo != repository || user == null) return;
      var removedDraft = false;
      for (final tableId in drafts.keys.toList()) {
        final previous = snapshot.orderFor(tableId);
        final latest = next.orderFor(tableId);
        if (previous != null && previous.id != latest?.id) {
          drafts.remove(tableId);
          _draftOrderIds.remove(tableId);
          staleDraftTables.add(tableId);
          removedDraft = true;
        }
      }
      snapshot = next;
      dishes = menu;
      offline = false;
      error = null;
      lastSync = DateTime.now();
      if (removedDraft) unawaited(_saveDrafts());
    } on ServiceException catch (e) {
      if (e.expired) {
        user = null;
        _timer?.cancel();
        drafts.clear();
      }
      offline = true;
      error = e.message;
    } catch (e) {
      offline = true;
      error = e.toString();
    } finally {
      _refreshing = false;
      loading = false;
      notifyListeners();
    }
  }

  List<CartLine> cart(String tableId) => drafts.putIfAbsent(tableId, () => []);
  double cartTotal(String tableId) =>
      cart(tableId).fold(0.0, (v, i) => v + i.quantity * i.price);
  int cartCount(String tableId) =>
      cart(tableId).fold(0, (v, i) => v + i.quantity);
  void add(String tableId, Dish dish, {StockBatch? batch}) {
    staleDraftTables.remove(tableId);
    final lines = cart(tableId);
    _draftOrderIds.putIfAbsent(tableId, () => snapshot.orderFor(tableId)?.id);
    final key = '${dish.id}:${batch?.id ?? ''}';
    final existing = lines.where((l) => l.key == key);
    final hadExisting = existing.isNotEmpty;
    final limit = batch?.quantity ?? dish.available;
    if (!hadExisting) {
      if (limit <= 0) {
        throw const ServiceException('This item is out of stock.');
      }
      if (lines.any((l) =>
          l.dish.id == dish.id &&
          l.batch?.id != batch?.id &&
          l.price == (batch?.price ?? dish.price))) {
        throw const ServiceException(
            'Use one batch per item at the same price.');
      }
      lines.add(CartLine(dish, batch: batch));
    } else {
      if (existing.first.quantity >= limit) {
        throw const ServiceException(
            'All available portions are already in your draft.');
      }
      existing.first.quantity++;
    }
    if (!_hasValidSharedStock(lines)) {
      if (!hadExisting) {
        lines.removeLast();
      } else {
        existing.first.quantity--;
      }
      throw const ServiceException(
          'These items share the same stock batch. Reduce the quantity before continuing.');
    }
    unawaited(_saveDrafts());
    notifyListeners();
  }

  void adjust(String tableId, CartLine line, int delta) {
    if (line.quantity + delta > line.limit) {
      throw const ServiceException('No more stock is available.');
    }
    line.quantity += delta;
    if (line.quantity <= 0) cart(tableId).remove(line);
    if (cart(tableId).isEmpty) _draftOrderIds.remove(tableId);
    unawaited(_saveDrafts());
    notifyListeners();
  }

  void clearCart(String tableId) {
    drafts.remove(tableId);
    _draftOrderIds.remove(tableId);
    unawaited(_saveDrafts());
    notifyListeners();
  }

  Future<void> acknowledge(String tableId) async {
    final started = uncertainSince[tableId];
    if (offline ||
        lastSync == null ||
        DateTime.now().difference(lastSync!).inSeconds > 15 ||
        (started != null && !lastSync!.isAfter(started))) {
      throw const ServiceException(
          'Refresh the live order after the last action before clearing this check.');
    }
    uncertainTables.remove(tableId);
    uncertainSince.remove(tableId);
    clearCart(tableId);
    await _saveUncertain();
    notifyListeners();
  }

  Future<void> perform(
      String tableId, Future<void> Function(WaiterRepository, Staff) action,
      {bool submitting = false}) async {
    if (busy) {
      throw const ServiceException(
          'Another action is still in progress. Please wait.');
    }
    if (user == null || repository == null) {
      throw const ServiceException('Sign in before changing an order.',
          expired: true);
    }
    if (offline) {
      throw const ServiceException(
          'Reconnect and refresh before changing an order.');
    }
    if (uncertainTables.contains(tableId)) {
      throw const ServiceException(
          'Review the previous action for this table first.');
    }
    busy = true;
    notifyListeners();
    final activeRepo = repository!;
    uncertainTables.add(tableId);
    uncertainSince[tableId] = DateTime.now();
    try {
      await _saveUncertain();
      await action(activeRepo, user!);
      uncertainTables.remove(tableId);
      uncertainSince.remove(tableId);
      await _saveUncertain();
      if (submitting) drafts.remove(tableId);
      if (submitting) _draftOrderIds.remove(tableId);
      await _saveDrafts();
      await refresh(reloadMenu: submitting);
    } on ServiceException catch (e) {
      if (!e.uncertain) {
        uncertainTables.remove(tableId);
        uncertainSince.remove(tableId);
        await _saveUncertain();
      }
      if (e.expired) {
        user = null;
        _timer?.cancel();
      }
      rethrow;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    repository?.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
