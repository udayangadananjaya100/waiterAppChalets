import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'models.dart';
import 'repository.dart';

class ConnectionConfig {
  final String server, supabaseUrl, publicKey;
  const ConnectionConfig(
      {required this.server,
      this.supabaseUrl = const String.fromEnvironment('SUPABASE_URL',
          defaultValue: 'https://ysejulbuvunfhodersjr.supabase.co'),
      this.publicKey = const String.fromEnvironment('SUPABASE_PUBLIC_KEY',
          defaultValue: 'sb_publishable_nn7GsENQXU_YmbYO7S8bUA_s8P4SVW5')});
  static String? validateServer(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.path.isNotEmpty && uri.path != '/')) {
      return 'Enter the admin website address, without a page path.';
    }
    final host = uri.host;
    final local = host == 'localhost' ||
        host == '10.0.2.2' ||
        host.startsWith('192.168.') ||
        host.startsWith('10.') ||
        host == '127.0.0.1' ||
        RegExp(r'^172\.(1[6-9]|2\d|3[01])\.').hasMatch(host);
    if (uri.scheme != 'https' &&
        !(uri.scheme == 'http' && local && !kReleaseMode)) {
      return 'Use an HTTPS address. Debug builds also support a local development server.';
    }
    return null;
  }

  Json toJson() =>
      {'server': server, 'supabaseUrl': supabaseUrl, 'publicKey': publicKey};
  factory ConnectionConfig.fromJson(Json j) => ConnectionConfig(
      server: j['server'] ?? '',
      supabaseUrl:
          j['supabaseUrl'] ?? const ConnectionConfig(server: '').supabaseUrl,
      publicKey:
          j['publicKey'] ?? const ConnectionConfig(server: '').publicKey);
}

class LiveRepository implements WaiterRepository {
  final ConnectionConfig config;
  final http.Client client;
  final FlutterSecureStorage storage;
  String? _cookie;
  LiveRepository(this.config,
      {http.Client? client, FlutterSecureStorage? storage})
      : client = client ?? http.Client(),
        storage = storage ?? const FlutterSecureStorage();
  @override
  bool get isDemo => false;

  Future<dynamic> _request(String method, Uri uri,
      {Json? body, bool database = false, bool authenticated = true}) async {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json'
    };
    if (database) {
      headers['apikey'] = config.publicKey;
      if (!config.publicKey.startsWith('sb_')) {
        headers['Authorization'] = 'Bearer ${config.publicKey}';
      }
      headers['Prefer'] = 'return=representation';
    } else if (_cookie != null && authenticated) {
      headers['Cookie'] = _cookie!;
    }
    final mutating = !['GET', 'HEAD'].contains(method);
    try {
      final req = http.Request(method, uri)
        ..followRedirects = false
        ..headers.addAll(headers);
      if (body != null) req.body = jsonEncode(body);
      final res =
          await (() async => http.Response.fromStream(await client.send(req)))()
              .timeout(const Duration(seconds: 20));
      dynamic data;
      try {
        data = jsonDecode(res.body);
      } catch (_) {
        data = null;
      }
      if (res.statusCode == 401 && uri.path.endsWith('/auth/login')) {
        throw ServiceException(data is Map
            ? '${data['error'] ?? 'Invalid credentials.'}'
            : 'Invalid credentials.');
      }
      if (res.statusCode == 401) {
        throw const ServiceException(
            'Your session has expired. Please sign in again.',
            expired: true);
      }
      if (res.statusCode < 200 || res.statusCode >= 300) {
        if (res.statusCode >= 500 && mutating) {
          throw const ServiceException(
              'The server could not confirm this action. Refresh and check the order before trying again.',
              uncertain: true);
        }
        throw ServiceException(data is Map
            ? '${data['error'] ?? data['message'] ?? 'The action was not accepted.'}'
            : 'The server returned ${res.statusCode}. Check the connection address.');
      }
      if (!database && uri.path.endsWith('/auth/login')) {
        final cookie = RegExp(r'(?:^|[,;]\s*)auth_token=([^;\s,]+)')
            .firstMatch(res.headers['set-cookie'] ?? '');
        if (cookie == null) {
          throw const ServiceException(
              'The server did not return a login session. Check the admin server configuration.');
        }
        _cookie = 'auth_token=${cookie.group(1)}';
      }
      return data;
    } on ServiceException {
      rethrow;
    } on TimeoutException {
      throw ServiceException(
          mutating
              ? 'The connection timed out. The action may have reached the server. Refresh and check before trying again.'
              : 'Connection timed out. Check Wi-Fi and try again.',
          uncertain: mutating);
    } catch (_) {
      throw ServiceException(
          mutating
              ? 'Connection lost. The action may have reached the server. Refresh and check before trying again.'
              : 'Unable to connect. Check Wi-Fi and the server address.',
          uncertain: mutating);
    }
  }

  Future<dynamic> api(String path, {String method = 'GET', Json? body}) =>
      _request(method,
          Uri.parse('${config.server.replaceAll(RegExp(r'/+$'), '')}$path'),
          body: body);
  Future<List<Json>> db(String table,
      {Map<String, String> query = const {},
      String method = 'GET',
      Json? body}) async {
    final uri = Uri.parse(
            '${config.supabaseUrl.replaceAll(RegExp(r'/+$'), '')}/rest/v1/$table')
        .replace(queryParameters: query);
    final data = await _request(method, uri, body: body, database: true);
    if (data is! List) {
      throw const ServiceException(
          'Unexpected database response. Ask your administrator to check the connection.');
    }
    return data.map((e) => Json.from(e)).toList();
  }

  Future<Staff> _currentUser() async {
    final data = await api('/api/auth/me');
    if (data is! Map || data['user'] == null) {
      throw const ServiceException(
          'Your session has expired. Please sign in again.',
          expired: true);
    }
    final user = Staff.fromJson(Json.from(data['user']));
    if (!user.canServe) {
      throw const ServiceException(
          'This account does not have waiter access. Contact your administrator.');
    }
    return user;
  }

  @override
  Future<Staff?> restore() async {
    final value = await storage.read(key: 'oruthota_session');
    if (value == null) return null;
    try {
      final stored = jsonDecode(value);
      if (stored['server'] != config.server) return null;
      _cookie = stored['cookie'];
      return await _currentUser();
    } on ServiceException catch (e) {
      if (!e.expired) rethrow;
      await storage.delete(key: 'oruthota_session');
      _cookie = null;
      return null;
    }
  }

  @override
  Future<Staff> login(String identifier, String password) async {
    final problem = ConnectionConfig.validateServer(config.server);
    if (problem != null) throw ServiceException(problem);
    await api('/api/auth/login', method: 'POST', body: {
      'identifier': identifier.trim(),
      'email': identifier.trim(),
      'password': password
    });
    final user = await _currentUser();
    await storage.write(
        key: 'oruthota_session',
        value: jsonEncode({'server': config.server, 'cookie': _cookie}));
    return user;
  }

  @override
  Future<void> logout() async {
    try {
      await api('/api/auth/logout', method: 'POST');
    } catch (_) {/* Local sign-out still succeeds offline. */}
    _cookie = null;
    await storage.delete(key: 'oruthota_session');
  }

  @override
  Future<FloorSnapshot> floor() async {
    final staff = await _currentUser();
    final values = await Future.wait([
      db('restaurant_tables',
          query: {'select': '*', 'order': 'table_number.asc'}),
      db('orders', query: {
        'select': '*',
        'status': 'in.(open,billed)',
        'order': 'created_at.desc'
      }),
      db('orders', query: {
        'select': '*',
        'status': 'eq.closed',
        'waiter_id': 'eq.${staff.id}',
        'order': 'created_at.desc',
        'limit': '20'
      }),
    ]);
    final orders =
        [...values[1], ...values[2]].map(ServiceOrder.fromJson).toList();
    final items = orders.isEmpty
        ? <Json>[]
        : await db('order_items', query: {
            'select': '*',
            'order_id': 'in.(${orders.map((e) => e.id).join(',')})'
          });
    return FloorSnapshot(values[0].map(DiningTable.fromJson).toList(), orders,
        items.map(OrderLine.fromJson).toList());
  }

  @override
  Future<OrderDetail> detail(String tableId) async {
    final data = await db('orders', query: {
      'select': '*',
      'table_id': 'eq.$tableId',
      'status': 'in.(open,billed)',
      'order': 'created_at.desc',
      'limit': '1'
    });
    if (data.isEmpty) return OrderDetail(null, []);
    final order = ServiceOrder.fromJson(data.first);
    final items = await db('order_items', query: {
      'select': '*',
      'order_id': 'eq.${order.id}',
      'order': 'created_at.asc'
    });
    return OrderDetail(order, items.map(OrderLine.fromJson).toList());
  }

  @override
  Future<List<Dish>> menu() async {
    final result = await api('/api/admin/menu-items');
    // The existing add-to-order endpoint deducts only the warehouse named Restaurant.
    // Restrict sellable batches to that exact warehouse, never another store's stock.
    final warehouses = await db('inventory_warehouses',
        query: {'select': 'id', 'name': 'eq.Restaurant'});
    final stock = warehouses.isEmpty
        ? <Json>[]
        : await db('inventory_stock', query: {
            'select': '*,batch:inventory_batches(*)',
            'warehouse_id': 'eq.${warehouses.first['id']}',
            'quantity': 'gt.0'
          });
    final pricing = await db('menu_item_batch_pricing',
        query: {'select': 'menu_item_id,batch_id,selling_price'});
    final today = DateTime.now().toUtc();
    final dateOnly = DateTime.utc(today.year, today.month, today.day);
    final dishes = <Dish>[];
    for (final raw in result['menuItems'] ?? []) {
      final j = Json.from(raw);
      if (j['availability'] != true || j['sell_type'] == 'Indirect') continue;
      final batches = <StockBatch>[];
      for (final s in stock) {
        if (s['item_id'] != j['linked_inventory_item_id'] ||
            s['batch'] == null) {
          continue;
        }
        final b = s['batch'];
        final expiry = DateTime.tryParse('${b['expiry_date']}');
        if (expiry != null && expiry.toUtc().isBefore(dateOnly)) continue;
        if (b['status'] != null && b['status'] != 'active') continue;
        final prices = pricing.where(
            (p) => p['menu_item_id'] == j['id'] && p['batch_id'] == b['id']);
        batches.add(StockBatch(
            '${b['id']}',
            '${b['batch_number'] ?? 'Batch'}',
            number(s['quantity']).floor(),
            prices.isEmpty
                ? number(j['price'])
                : number(prices.first['selling_price']),
            expiry));
      }
      batches.sort((a, b) =>
          (a.expires ?? DateTime(9999)).compareTo(b.expires ?? DateTime(9999)));
      dishes.add(Dish.fromJson(j, batches: batches));
    }
    return dishes;
  }

  Future<OrderDetail> _guard(ServiceOrder expected, Staff staff,
      {bool allowBilled = false}) async {
    final current = await _currentUser();
    if (current.id != staff.id) {
      throw const ServiceException(
          'Your signed-in account changed. Sign in again.',
          expired: true);
    }
    final fresh = await detail(expected.tableId);
    if (fresh.order?.id != expected.id) {
      throw const ServiceException(
          'This order has changed. Refresh the table.');
    }
    if (fresh.order!.waiterId != staff.id) {
      throw const ServiceException(
          'Only the assigned waiter can change this order.');
    }
    if (fresh.order!.billed && !allowBilled) {
      throw const ServiceException(
          'This bill is with the cashier. Ask the cashier before changing it.');
    }
    return fresh;
  }

  @override
  Future<void> submit(DiningTable table, Staff staff, List<CartLine> lines,
      String mobile) async {
    await _currentUser();
    final fresh = await detail(table.id);
    if (fresh.order?.lockedFor(staff) == true) {
      throw const ServiceException('Another waiter is handling this table.');
    }
    if (fresh.order?.billed == true) {
      throw const ServiceException('This bill is already with the cashier.');
    }
    if (lines.isEmpty) throw const ServiceException('Add at least one item.');
    final currentMenu = await menu();
    for (final line in lines) {
      final found = currentMenu.where((d) => d.id == line.dish.id);
      if (found.isEmpty) {
        throw ServiceException(
            '${line.dish.name} is no longer on the menu. Remove it from your draft.');
      }
      final dish = found.first;
      final batches = dish.batches.where((b) => b.id == line.batch?.id);
      final stock = dish.needsBatch
          ? (batches.isEmpty ? 0 : batches.first.quantity)
          : dish.available;
      final price = dish.needsBatch && batches.isNotEmpty
          ? batches.first.price
          : dish.price;
      if (line.quantity < 1 || line.quantity > stock) {
        throw ServiceException(
            'Not enough stock for ${dish.name}. Update your draft.');
      }
      if ((price - line.price).abs() > .001) {
        throw ServiceException(
            '${dish.name} has a new price. Remove it and add it again.');
      }
      // The existing endpoint merges identical menu item + price, ignoring batch ID.
      final samePrice = fresh.items.where(
          (i) => i.menuItemId == dish.id && (i.price - price).abs() < .001);
      if (samePrice.any((i) => i.batchId != line.batch?.id)) {
        throw ServiceException(
            '${dish.name} is already ordered from another batch at this price. Ask the cashier to handle the batch change.');
      }
    }
    // Never retry this endpoint automatically: it is not idempotent.
    final result = await api('/api/waiter/add-to-order', method: 'POST', body: {
      'table_id': table.id,
      'table_number': table.number,
      'table_status': table.status,
      'order_id': fresh.order?.id,
      'customer_mobile': mobile.trim().isEmpty ? null : mobile.trim(),
      'items': lines.map((l) => l.toPayload()).toList()
    });
    if (result is! Map || result['order_id'] == null) {
      throw const ServiceException(
          'The server did not confirm the order. Refresh and check it.',
          uncertain: true);
    }
    try {
      final after = await detail(table.id);
      for (final line in lines) {
        int count(List<OrderLine> items) => items
            .where((i) =>
                i.menuItemId == line.dish.id &&
                (i.price - line.price).abs() < .001)
            .fold(0, (n, i) => n + i.quantity);
        if (count(after.items) < count(fresh.items) + line.quantity) {
          throw const ServiceException(
              'Some items were not confirmed. Compare the live order with your draft before continuing.',
              uncertain: true);
        }
      }
    } on ServiceException {
      throw const ServiceException(
          'The order was sent, but could not be fully verified. Refresh and compare it with your draft before continuing.',
          uncertain: true);
    }
  }

  @override
  Future<void> sendToCashier(ServiceOrder order, Staff staff) async {
    final fresh = await _guard(order, staff);
    if (fresh.items.isEmpty) {
      throw const ServiceException(
          'An empty order cannot be sent to the cashier.');
    }
    final changed = await db('orders', method: 'PATCH', query: {
      'id': 'eq.${order.id}',
      'waiter_id': 'eq.${staff.id}',
      'status': 'eq.open'
    }, body: {
      'status': 'billed',
      'updated_at': DateTime.now().toUtc().toIso8601String()
    });
    if (changed.isEmpty) {
      throw const ServiceException('The order changed. Refresh and try again.');
    }
    // Keep table occupied. Only the existing cashier flow settles payment and frees it.
  }

  @override
  Future<void> serve(ServiceOrder order, OrderLine line, Staff staff) async {
    final fresh = await _guard(order, staff);
    final matches = fresh.items.where((i) => i.id == line.id);
    if (matches.isEmpty) {
      throw const ServiceException('This item has changed. Refresh the order.');
    }
    final item = matches.first;
    final menuItems = await menu();
    final direct =
        menuItems.any((d) => d.id == item.menuItemId && d.inventoried);
    final amount =
        direct ? item.quantity : item.readyQuantity.clamp(0, item.quantity);
    if (amount <= item.served) {
      throw const ServiceException('No additional portions are ready yet.');
    }
    final changed = await db('order_items', method: 'PATCH', query: {
      'id': 'eq.${line.id}',
      'order_id': 'eq.${order.id}',
      'quantity': 'eq.${item.quantity}'
    }, body: {
      'served_quantity': amount
    });
    if (changed.isEmpty) {
      throw const ServiceException('This item changed. Refresh the order.');
    }
  }

  @override
  Future<void> release(ServiceOrder order, Staff staff) async {
    await _guard(order, staff, allowBilled: true);
    await api('/api/waiter/release-table',
        method: 'POST', body: {'table_id': order.tableId});
  }

  @override
  Future<Json> findGuest(String code) async {
    final result = await api(
        '/api/admin/front-desk/guest-pass?code=${Uri.encodeComponent(code.trim())}');
    if (result is! Map || result['customer'] is! Map) {
      throw const ServiceException('No checked-in guest matches this pass.');
    }
    return Json.from(result['customer']);
  }

  @override
  Future<void> attachGuest(ServiceOrder order, Json guest, Staff staff) async {
    await _guard(order, staff);
    final changed = await db('orders', method: 'PATCH', query: {
      'id': 'eq.${order.id}',
      'waiter_id': 'eq.${staff.id}',
      'status': 'eq.open'
    }, body: {
      'customer_id': guest['id'],
      if (guest['phone'] != null) 'customer_mobile': guest['phone'],
      'updated_at': DateTime.now().toUtc().toIso8601String()
    });
    if (changed.isEmpty) {
      throw const ServiceException('This order changed. Refresh the table.');
    }
  }

  @override
  void dispose() => client.close();
}
