import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:oruthota_waiter/data/models.dart';
import 'package:oruthota_waiter/data/demo_repository.dart';
import 'package:oruthota_waiter/data/live_repository.dart';
import 'package:oruthota_waiter/state/app_controller.dart';

class UncertainRepository extends DemoRepository {
  int attempts = 0;
  @override
  Future<void> submit(DiningTable table, Staff staff, List<CartLine> lines,
      String mobile) async {
    attempts++;
    throw const ServiceException('The network response was lost.',
        uncertain: true);
  }
}

class PersistentTestRepository extends DemoRepository {
  @override
  bool get isDemo => false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('A zero batch selling price stays zero, and stock limits are enforced',
      () {
    final app = AppController();
    final dish = Dish(
        id: 'drink',
        name: 'Drink',
        category: 'Drinks',
        price: 500,
        stockType: 'Inventoried',
        inventoryId: 'inv');
    final batch = StockBatch('batch', 'Fresh', 1, 0, null);
    app.add('table', dish, batch: batch);
    expect(app.cartTotal('table'), 0);
    expect(() => app.add('table', dish, batch: batch),
        throwsA(isA<ServiceException>()));
    app.adjust('table', app.cart('table').single, -1);
    expect(app.cartCount('table'), 0);
    app.dispose();
  });
  test(
      'An ambiguous submission remains locked and is never automatically retried',
      () async {
    final repo = UncertainRepository();
    final app = AppController()
      ..repository = repo
      ..user = DemoRepository.staff;
    await app.refresh();
    final table = app.snapshot.tables.first;
    app.add(table.id, app.dishes.first);
    Future<void> submit() => app.perform(
        table.id, (r, s) => r.submit(table, s, app.cart(table.id), ''),
        submitting: true);
    await expectLater(submit(), throwsA(isA<ServiceException>()));
    expect(app.uncertainTables, contains(table.id));
    expect(app.cartCount(table.id), 1);
    await expectLater(submit(), throwsA(isA<ServiceException>()));
    expect(repo.attempts, 1);
    await expectLater(
        app.acknowledge(table.id), throwsA(isA<ServiceException>()));
    await app.refresh();
    await app.acknowledge(table.id);
    expect(app.uncertainTables, isEmpty);
    expect(app.cartCount(table.id), 0);
    app.dispose();
  });
  test('Prepared and served quantities distinguish partially ready dishes', () {
    final item = OrderLine.fromJson({
      'id': 'i',
      'order_id': 'o',
      'name': 'Rice',
      'price': '1250.50',
      'quantity': 4,
      'prepared_quantity': 3,
      'served_quantity': 2,
      'kitchen_status': 'preparing'
    });
    expect(item.readyToServe, isTrue);
    expect(item.readyQuantity - item.served, 1);
    expect(item.fullyServed, isFalse);
    expect(item.price, 1250.5);
  });
  test('Shared inventory batches enforce their combined draft quantity', () {
    final app = AppController();
    final batch = StockBatch('batch', 'Shared batch', 5, 100, null);
    Dish dish(String id) => Dish(
        id: id,
        name: id,
        category: 'Drinks',
        price: 100,
        stockType: 'Inventoried',
        inventoryId: 'shared-item',
        batches: [batch]);
    app.add('table', dish('first'), batch: batch);
    for (var i = 0; i < 3; i++) {
      app.add('table', dish('first'), batch: batch);
    }
    app.add('table', dish('second'), batch: batch);
    expect(() => app.add('table', dish('second'), batch: batch),
        throwsA(isA<ServiceException>()));
    expect(app.cartCount('table'), 5);
    app.dispose();
  });
  test('Batch pricing is shown instead of a different base menu price', () {
    final onePrice = Dish(
        id: 'one',
        name: 'One',
        category: 'Drinks',
        price: 500,
        stockType: 'Inventoried',
        inventoryId: 'stock',
        batches: [StockBatch('a', 'A', 2, 450, null)]);
    final range = Dish(
        id: 'range',
        name: 'Range',
        category: 'Drinks',
        price: 500,
        stockType: 'Inventoried',
        inventoryId: 'stock',
        batches: [
          StockBatch('a', 'A', 2, 450, null),
          StockBatch('b', 'B', 2, 475, null)
        ]);
    expect(onePrice.displayPrice, 'LKR 450.00');
    expect(range.displayPrice, 'From LKR 450.00');
  });
  test('An unsent draft is restored after the app controller restarts',
      () async {
    SharedPreferences.setMockInitialValues({
      'connection':
          '{"server":"https://restaurant.test","supabaseUrl":"https://database.test","publicKey":"sb_publishable_test"}'
    });
    final preferences = await SharedPreferences.getInstance();
    final first = AppController(
        preferences: preferences,
        config: const ConnectionConfig(server: 'https://restaurant.test'))
      ..repository = PersistentTestRepository()
      ..user = DemoRepository.staff;
    await first.refresh();
    first.add('t1', first.dishes.first);
    await Future<void>.delayed(Duration.zero);
    first.dispose();

    final restarted = AppController(
        preferences: preferences,
        repositoryFactory: (_) => PersistentTestRepository());
    await restarted.initialize();
    expect(restarted.cartCount('t1'), 1);
    expect(restarted.cart('t1').single.dish.id, first.dishes.first.id);
    restarted.dispose();
  });
  test(
      'Connection settings reject non-HTTPS public hosts and embedded credentials',
      () {
    expect(
        ConnectionConfig.validateServer('https://admin.example.com'), isNull);
    expect(ConnectionConfig.validateServer('http://public.example.com'),
        isNotNull);
    expect(ConnectionConfig.validateServer('https://user:password@example.com'),
        isNotNull);
    expect(ConnectionConfig.validateServer('https://example.com/dashboard'),
        isNotNull);
  });
}
