import 'models.dart';

abstract class WaiterRepository {
  bool get isDemo;
  Future<Staff?> restore();
  Future<Staff> login(String identifier, String password);
  Future<void> logout();
  Future<FloorSnapshot> floor();
  Future<List<Dish>> menu();
  Future<OrderDetail> detail(String tableId);
  Future<void> submit(
      DiningTable table, Staff staff, List<CartLine> lines, String mobile);
  Future<void> sendToCashier(ServiceOrder order, Staff staff);
  Future<void> serve(ServiceOrder order, OrderLine line, Staff staff);
  Future<void> release(ServiceOrder order, Staff staff);
  Future<Json> findGuest(String code);
  Future<void> attachGuest(ServiceOrder order, Json guest, Staff staff);
  void dispose();
}
