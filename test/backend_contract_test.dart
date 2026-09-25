import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:oruthota_waiter/data/live_repository.dart';
import 'package:oruthota_waiter/data/models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  final staff = {
    'id': 'waiter-1',
    'name': 'Test Waiter',
    'role': 'waiter',
    'permissions': []
  };
  const config = ConnectionConfig(
      server: 'https://restaurant.test',
      supabaseUrl: 'https://database.test',
      publicKey: 'sb_publishable_test');
  test(
      'Existing HTTP-only Set-Cookie login works without a token response or backend changes',
      () async {
    final seen = <http.Request>[];
    final client = MockClient((request) async {
      seen.add(request);
      if (request.url.path == '/api/auth/login') {
        expect(jsonDecode(request.body)['identifier'], '0012');
        return http.Response(
            jsonEncode({
              'user': {...staff, 'password': 'must-not-be-stored'}
            }),
            200,
            headers: {
              'set-cookie':
                  'auth_token=fixture-token; Path=/; HttpOnly; Secure; SameSite=Strict'
            });
      }
      if (request.url.path == '/api/auth/me') {
        expect(request.headers['Cookie'], 'auth_token=fixture-token');
        expect(request.headers.containsKey('Authorization'), isFalse);
        return http.Response(jsonEncode({'user': staff}), 200);
      }
      if (request.url.host == 'database.test') {
        expect(request.headers['apikey'], 'sb_publishable_test');
        expect(request.headers.containsKey('Cookie'), isFalse);
        expect(request.headers.containsKey('Authorization'), isFalse);
        return http.Response('[]', 200);
      }
      return http.Response('{}', 404);
    });
    final repo = LiveRepository(config, client: client);
    expect((await repo.login('0012', 'test-password')).id, 'waiter-1');
    await repo.floor();
    final saved =
        await const FlutterSecureStorage().read(key: 'oruthota_session');
    expect(saved, contains('fixture-token'));
    expect(saved, isNot(contains('test-password')));
    expect(saved, isNot(contains('must-not-be-stored')));
    expect(seen.every((r) => !r.followRedirects), isTrue);
    repo.dispose();
  });
  test('Bill mutation rechecks table ownership before any write', () async {
    int writes = 0;
    final repo = LiveRepository(config, client: MockClient((r) async {
      if (r.method == 'PATCH') writes++;
      if (r.url.path == '/api/auth/me') {
        return http.Response(jsonEncode({'user': staff}), 200);
      }
      if (r.url.path.endsWith('/orders')) {
        return http.Response(
            jsonEncode([
              {
                'id': 'o',
                'table_id': 't',
                'status': 'open',
                'waiter_id': 'someone-else',
                'total_price': 1000
              }
            ]),
            200);
      }
      if (r.url.path.endsWith('/order_items')) return http.Response('[]', 200);
      return http.Response('{}', 404);
    }));
    final order = ServiceOrder(
        id: 'o',
        tableId: 't',
        status: 'open',
        total: 1000,
        waiterId: 'waiter-1');
    await expectLater(repo.sendToCashier(order, Staff.fromJson(staff)),
        throwsA(isA<ServiceException>()));
    expect(writes, 0);
    repo.dispose();
  });
  test('Expired batches are hidden and only Restaurant warehouse stock is used',
      () async {
    final repo = LiveRepository(config, client: MockClient((r) async {
      if (r.url.path.endsWith('/menu-items')) {
        return http.Response(
            jsonEncode({
              'menuItems': [
                {
                  'id': 'm',
                  'name': 'Cola',
                  'availability': true,
                  'sell_type': 'Direct',
                  'stock_type': 'Inventoried',
                  'linked_inventory_item_id': 'inv',
                  'price': 500
                }
              ]
            }),
            200);
      }
      if (r.url.path.endsWith('/inventory_warehouses')) {
        expect(r.url.queryParameters['name'], 'eq.Restaurant');
        return http.Response('[{"id":"restaurant-store"}]', 200);
      }
      if (r.url.path.endsWith('/inventory_stock')) {
        expect(r.url.queryParameters['warehouse_id'], 'eq.restaurant-store');
        return http.Response(
            jsonEncode([
              {
                'item_id': 'inv',
                'quantity': 5,
                'batch': {
                  'id': 'old',
                  'status': 'active',
                  'expiry_date': '2020-01-01'
                }
              },
              {
                'item_id': 'inv',
                'quantity': 3,
                'batch': {
                  'id': 'new',
                  'status': 'active',
                  'expiry_date': '2099-01-01'
                }
              },
            ]),
            200);
      }
      if (r.url.path.endsWith('/menu_item_batch_pricing')) {
        return http.Response(
            '[{"menu_item_id":"m","batch_id":"new","selling_price":0}]', 200);
      }
      return http.Response('{}', 404);
    }));
    final dish = (await repo.menu()).single;
    expect(dish.batches.single.id, 'new');
    expect(dish.batches.single.price, 0);
    expect(dish.available, 3);
    repo.dispose();
  });
}
