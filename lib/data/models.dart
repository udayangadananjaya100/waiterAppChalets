import 'package:intl/intl.dart';

typedef Json = Map<String, dynamic>;
double number(dynamic value) => double.tryParse('$value') ?? 0;
String money(num value) => 'LKR ${NumberFormat('#,##0.00').format(value)}';

class Staff {
  final String id, name, role;
  final List<String> permissions;
  final bool restricted;
  Staff(this.id, this.name, this.role,
      {this.permissions = const [], this.restricted = false});
  factory Staff.fromJson(Json j) =>
      Staff('${j['id']}', '${j['name'] ?? 'Team member'}', '${j['role']}',
          permissions: List<String>.from(j['permissions'] ?? []),
          restricted: j['restrict_admin_permissions'] == true);
  bool get canServe =>
      role == 'waiter' ||
      (role == 'admin' && !restricted) ||
      permissions.contains('/dashboard') ||
      permissions.contains('/dashboard/pos');
  String get firstName => name.split(' ').first;
}

class DiningTable {
  final String id, section, status;
  final int number, capacity;
  DiningTable(this.id, this.number, this.section, this.status, this.capacity);
  factory DiningTable.fromJson(Json j) => DiningTable(
      '${j['id']}',
      (j['table_number'] as num).toInt(),
      '${j['location'] ?? 'Restaurant'}',
      '${j['status'] ?? 'available'}',
      (j['capacity'] as num?)?.toInt() ?? 0);
}

class ServiceOrder {
  final String id, tableId, status;
  final String? waiterId, waiterName, customerMobile, customerId, billNumber;
  final double total;
  final double? confirmedTotal;
  final DateTime? createdAt;
  final Json? breakdown;
  ServiceOrder(
      {required this.id,
      required this.tableId,
      required this.status,
      required this.total,
      this.waiterId,
      this.waiterName,
      this.customerMobile,
      this.customerId,
      this.billNumber,
      this.confirmedTotal,
      this.createdAt,
      this.breakdown});
  factory ServiceOrder.fromJson(Json j) => ServiceOrder(
      id: '${j['id']}',
      tableId: '${j['table_id']}',
      status: '${j['status']}',
      total: number(j['total_price']),
      waiterId: j['waiter_id'],
      waiterName: j['waiter_name'],
      customerMobile: j['customer_mobile'],
      customerId: j['customer_id'],
      billNumber: j['bill_number'],
      confirmedTotal:
          j['confirmed_total'] == null ? null : number(j['confirmed_total']),
      createdAt: DateTime.tryParse('${j['created_at']}'),
      breakdown:
          j['bill_breakdown'] is Map ? Json.from(j['bill_breakdown']) : null);
  bool get billed => status == 'billed';
  bool get active => status == 'open' || billed;
  bool ownedBy(Staff staff) => waiterId == staff.id;
  bool lockedFor(Staff staff) => waiterId != null && waiterId != staff.id;
}

class OrderLine {
  final String id, orderId, name, kitchenStatus;
  final String? menuItemId, batchId;
  final double price;
  final int quantity, prepared, served;
  OrderLine(
      {required this.id,
      required this.orderId,
      required this.name,
      required this.price,
      required this.quantity,
      this.menuItemId,
      this.batchId,
      this.kitchenStatus = 'pending',
      this.prepared = 0,
      this.served = 0});
  factory OrderLine.fromJson(Json j) => OrderLine(
      id: '${j['id']}',
      orderId: '${j['order_id']}',
      name: '${j['name']}',
      price: number(j['price']),
      quantity: number(j['quantity']).toInt(),
      menuItemId: j['menu_item_id'],
      batchId: j['batch_id'],
      kitchenStatus: '${j['kitchen_status'] ?? 'pending'}',
      prepared: number(j['prepared_quantity']).toInt(),
      served: number(j['served_quantity']).toInt());
  int get readyQuantity => prepared > 0
      ? prepared
      : (['ready', 'done'].contains(kitchenStatus) ? quantity : 0);
  bool get readyToServe => readyQuantity > served;
  bool get fullyServed => served >= quantity;
}

class StockBatch {
  final String id, label;
  final int quantity;
  final double price;
  final DateTime? expires;
  StockBatch(this.id, this.label, this.quantity, this.price, this.expires);
}

class Dish {
  final String id, name, description, category, stockType;
  final String? inventoryId;
  final double price;
  final int manualStock;
  final List<StockBatch> batches;
  Dish(
      {required this.id,
      required this.name,
      required this.category,
      required this.price,
      this.description = '',
      this.stockType = 'Non-Inventoried',
      this.inventoryId,
      this.manualStock = 0,
      this.batches = const []});
  bool get inventoried => stockType == 'Inventoried';
  bool get needsBatch => inventoried && inventoryId != null;
  int get available => !inventoried
      ? 9999
      : needsBatch
          ? batches.fold(0, (a, b) => a + b.quantity)
          : manualStock;
  bool get availableToOrder => available > 0;
  factory Dish.fromJson(Json j, {List<StockBatch> batches = const []}) => Dish(
      id: '${j['id']}',
      name: '${j['name']}',
      category: '${j['category'] ?? 'Other'}',
      description: '${j['description'] ?? ''}',
      price: number(j['price']),
      stockType: '${j['stock_type'] ?? 'Non-Inventoried'}',
      inventoryId: j['linked_inventory_item_id'],
      manualStock: number(j['stock']).toInt(),
      batches: batches);
}

class CartLine {
  final Dish dish;
  final StockBatch? batch;
  int quantity;
  CartLine(this.dish, {this.batch, this.quantity = 1});
  String get key => '${dish.id}:${batch?.id ?? ''}';
  double get price => batch?.price ?? dish.price;
  int get limit => batch?.quantity ?? dish.available;
  Json toPayload() => {
        'menu_item_id': dish.id,
        'batch_id': batch?.id,
        'name': dish.name,
        'price': price,
        'quantity': quantity,
        'stock_type': dish.stockType,
        'linked_inventory_item_id': dish.inventoryId
      };
}

class FloorSnapshot {
  final List<DiningTable> tables;
  final List<ServiceOrder> orders;
  final List<OrderLine> items;
  FloorSnapshot(this.tables, this.orders, this.items);
  ServiceOrder? orderFor(String tableId) {
    for (final order in orders) {
      if (order.tableId == tableId && order.active) return order;
    }
    return null;
  }
}

class OrderDetail {
  final ServiceOrder? order;
  final List<OrderLine> items;
  OrderDetail(this.order, this.items);
}

class ServiceException implements Exception {
  final String message;
  final bool expired, uncertain;
  const ServiceException(this.message,
      {this.expired = false, this.uncertain = false});
  @override
  String toString() => message;
}
