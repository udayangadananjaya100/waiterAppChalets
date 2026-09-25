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
  ConnectionConfig config;
  WaiterRepository? repository;
  Staff? user;
  FloorSnapshot snapshot = FloorSnapshot([], [], []);
  List<Dish> dishes = [];
  final Map<String, List<CartLine>> drafts = {};
  final Set<String> uncertainTables = {};
  final Set<String> staleDraftTables = {};
  Timer? _timer;
  bool busy = false, loading = false, offline = false, _refreshing = false;
  String? error;
  DateTime? lastSync;
  bool get demo => repository?.isDemo == true;
  bool get configured => config.server.isNotEmpty;
  AppController({this.preferences, ConnectionConfig? config})
      : config = config ??
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
    repository = LiveRepository(config);
    loading = true;
    notifyListeners();
    try {
      user = await repository!.restore();
      if (user != null) {
        _restoreUncertain();
        await refresh();
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
      repository = LiveRepository(config);
      user = await repository!.login(identifier, password);
      _restoreUncertain();
      await refresh();
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
    staleDraftTables.clear();
    await refresh();
    _startTimer();
  }

  String get _pendingKey => 'pending:${config.server}:${user?.id}';
  void _restoreUncertain() {
    uncertainTables
      ..clear()
      ..addAll(preferences?.getStringList(_pendingKey) ?? []);
  }

  Future<void> _saveUncertain() async {
    if (!demo) {
      await preferences?.setStringList(_pendingKey, uncertainTables.toList());
    }
  }

  Future<void> signOut() async {
    _timer?.cancel();
    final old = repository;
    user = null;
    drafts.clear();
    dishes = [];
    snapshot = FloorSnapshot([], [], []);
    uncertainTables.clear();
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
      for (final tableId in drafts.keys.toList()) {
        final previous = snapshot.orderFor(tableId);
        final latest = next.orderFor(tableId);
        if (previous != null && previous.id != latest?.id) {
          drafts.remove(tableId);
          staleDraftTables.add(tableId);
        }
      }
      snapshot = next;
      dishes = menu;
      offline = false;
      error = null;
      lastSync = DateTime.now();
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
    final key = '${dish.id}:${batch?.id ?? ''}';
    final existing = lines.where((l) => l.key == key);
    final limit = batch?.quantity ?? dish.available;
    if (existing.isEmpty) {
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
    notifyListeners();
  }

  void adjust(String tableId, CartLine line, int delta) {
    if (line.quantity + delta > line.limit) {
      throw const ServiceException('No more stock is available.');
    }
    line.quantity += delta;
    if (line.quantity <= 0) cart(tableId).remove(line);
    notifyListeners();
  }

  void clearCart(String tableId) {
    drafts.remove(tableId);
    notifyListeners();
  }

  Future<void> acknowledge(String tableId) async {
    if (offline ||
        lastSync == null ||
        DateTime.now().difference(lastSync!).inSeconds > 15) {
      throw const ServiceException(
          'Refresh the live order before clearing this check.');
    }
    uncertainTables.remove(tableId);
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
    try {
      await _saveUncertain();
      await action(activeRepo, user!);
      uncertainTables.remove(tableId);
      await _saveUncertain();
      if (submitting) drafts.remove(tableId);
      await refresh(reloadMenu: submitting);
    } on ServiceException catch (e) {
      if (!e.uncertain) {
        uncertainTables.remove(tableId);
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
