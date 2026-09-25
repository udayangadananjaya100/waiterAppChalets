import 'package:flutter_test/flutter_test.dart';
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
