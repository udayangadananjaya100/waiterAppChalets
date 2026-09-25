import 'models.dart';
import 'repository.dart';

class DemoRepository implements WaiterRepository {
  static final staff = Staff('demo-waiter', 'Kasun Perera', 'waiter');
  final List<DiningTable> _tables = List.generate(
      12,
      (i) => DiningTable(
          't${i + 1}',
          i + 1,
          i < 6 ? 'Garden terrace' : 'Main restaurant',
          i == 4
              ? 'reserved'
              : [1, 2, 7].contains(i)
                  ? 'occupied'
                  : 'available',
          i % 3 == 0 ? 6 : 4));
  final List<Json> _orders = [];
  final List<Json> _items = [];
  int _sequence = 10;
  final List<Dish> _menu = [
    Dish(
        id: 'm1',
        name: 'Sri Lankan rice & curry',
        category: 'Mains',
        description: 'Seasonal vegetables, fragrant rice and house sambols.',
        price: 1850),
    Dish(
        id: 'm2',
        name: 'Grilled lake fish',
        category: 'Mains',
        description: 'Herb-marinated fish, garden greens and lime.',
        price: 2850),
    Dish(
        id: 'm3',
        name: 'Chicken kottu',
        category: 'Mains',
        description: 'Chopped roti, tender chicken and warming spices.',
        price: 1650),
    Dish(
        id: 'm4',
        name: 'Garden fresh salad',
        category: 'Starters',
        description: 'Crisp leaves, cucumber and a citrus dressing.',
        price: 950),
    Dish(
        id: 'm5',
        name: 'Crispy calamari',
        category: 'Starters',
        description: 'Golden calamari with a house chilli dip.',
        price: 1450),
    Dish(
        id: 'm6',
        name: 'Fresh lime soda',
        category: 'Drinks',
        description: 'Freshly squeezed lime, soda and a touch of mint.',
        price: 650),
    Dish(
        id: 'm7',
        name: 'King coconut',
        category: 'Drinks',
        description: 'Naturally refreshing. Served chilled.',
        price: 450,
        stockType: 'Inventoried',
        manualStock: 12),
    Dish(
        id: 'm8',
        name: 'Ceylon iced tea',
        category: 'Drinks',
        description: 'Slow-brewed Ceylon tea with fresh lemon.',
        price: 550),
    Dish(
        id: 'm9',
        name: 'Warm chocolate brownie',
        category: 'Desserts',
        description: 'Rich chocolate brownie with vanilla ice cream.',
        price: 1150),
    Dish(
        id: 'm10',
        name: 'Traditional wattalappam',
        category: 'Desserts',
        description: 'Coconut custard, kithul jaggery and cardamom.',
        price: 750),
  ];
  DemoRepository() {
    for (final entry in [
      (2, 'open', 'demo-waiter', 'Kasun Perera'),
      (3, 'open', 'other', 'Nimal Silva'),
      (8, 'billed', 'demo-waiter', 'Kasun Perera')
    ]) {
      _orders.add({
        'id': 'o${entry.$1}',
        'table_id': 't${entry.$1}',
        'status': entry.$2,
        'total_price': 4350,
        'waiter_id': entry.$3,
        'waiter_name': entry.$4,
        'created_at': DateTime.now()
            .subtract(const Duration(minutes: 14))
            .toIso8601String(),
        if (entry.$2 == 'billed') 'confirmed_total': 4785.0
      });
      _items.addAll([
        {
          'id': 'i${entry.$1}a',
          'order_id': 'o${entry.$1}',
          'menu_item_id': 'm1',
          'name': 'Sri Lankan rice & curry',
          'price': 1850,
          'quantity': 2,
          'prepared_quantity': 2,
          'served_quantity': 0,
          'kitchen_status': 'ready'
        },
        {
          'id': 'i${entry.$1}b',
          'order_id': 'o${entry.$1}',
          'menu_item_id': 'm6',
          'name': 'Fresh lime soda',
          'price': 650,
          'quantity': 1,
          'prepared_quantity': 0,
          'served_quantity': 0,
          'kitchen_status': 'preparing'
        },
      ]);
    }
  }
  @override
  bool get isDemo => true;
  @override
  Future<Staff?> restore() async => staff;
  @override
  Future<Staff> login(String identifier, String password) async => staff;
  @override
  Future<void> logout() async {}
  @override
  Future<FloorSnapshot> floor() async => FloorSnapshot(
      _tables
          .map((t) => DiningTable(
              t.id,
              t.number,
              t.section,
              _orders.any((o) => o['table_id'] == t.id) ? 'occupied' : t.status,
              t.capacity))
          .toList(),
      _orders.map(ServiceOrder.fromJson).toList(),
      _items.map(OrderLine.fromJson).toList());
  @override
  Future<List<Dish>> menu() async => _menu;
  @override
  Future<OrderDetail> detail(String tableId) async {
    final orders = _orders.where((o) => o['table_id'] == tableId);
    if (orders.isEmpty) return OrderDetail(null, []);
    return OrderDetail(
        ServiceOrder.fromJson(orders.first),
        _items
            .where((i) => i['order_id'] == orders.first['id'])
            .map(OrderLine.fromJson)
            .toList());
  }

  @override
  Future<void> submit(DiningTable table, Staff staff, List<CartLine> lines,
      String mobile) async {
    final existing = _orders.where((o) => o['table_id'] == table.id);
    final Json order;
    if (existing.isEmpty) {
      order = {
        'id': 'o${++_sequence}',
        'table_id': table.id,
        'status': 'open',
        'total_price': 0.0,
        'waiter_id': staff.id,
        'waiter_name': staff.name,
        'created_at': DateTime.now().toIso8601String()
      };
      _orders.add(order);
    } else {
      order = existing.first;
    }
    order['waiter_id'] = staff.id;
    order['waiter_name'] = staff.name;
    order['customer_mobile'] = mobile;
    for (final line in lines) {
      final match = _items.where((i) =>
          i['order_id'] == order['id'] && i['menu_item_id'] == line.dish.id);
      if (match.isNotEmpty) {
        match.first['quantity'] += line.quantity;
        match.first['kitchen_status'] = 'preparing';
      } else {
        _items.add({
          'id': 'i${++_sequence}',
          'order_id': order['id'],
          'menu_item_id': line.dish.id,
          'name': line.dish.name,
          'price': line.price,
          'quantity': line.quantity,
          'kitchen_status': 'pending',
          'prepared_quantity': 0,
          'served_quantity': 0
        });
      }
      order['total_price'] =
          number(order['total_price']) + line.price * line.quantity;
    }
  }

  @override
  Future<void> sendToCashier(ServiceOrder order, Staff staff) async {
    final target = _orders.firstWhere((o) => o['id'] == order.id);
    target['status'] = 'billed';
    target['confirmed_total'] = number(target['total_price']) * 1.1;
  }

  @override
  Future<void> serve(ServiceOrder order, OrderLine line, Staff staff) async {
    _items.firstWhere((i) => i['id'] == line.id)['served_quantity'] =
        line.readyQuantity > 0 ? line.readyQuantity : line.quantity;
  }

  @override
  Future<void> release(ServiceOrder order, Staff staff) async {
    final target = _orders.firstWhere((o) => o['id'] == order.id);
    target['waiter_id'] = null;
    target['waiter_name'] = null;
  }

  @override
  Future<Json> findGuest(String code) async => {
        'id': 'guest-demo',
        'name': 'Alex Morgan',
        'phone': '0771234567',
        'current_room': 'Chalet 04'
      };
  @override
  Future<void> attachGuest(ServiceOrder order, Json guest, Staff staff) async {
    final target = _orders.firstWhere((o) => o['id'] == order.id);
    target['customer_id'] = guest['id'];
    target['customer_mobile'] = guest['phone'];
  }

  @override
  void dispose() {}
}
