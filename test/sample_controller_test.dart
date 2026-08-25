import 'package:cashinator/data/db/app_database.dart';
import 'package:cashinator/data/models/payment_method.dart';
import 'package:cashinator/repositories/order_repository.dart';
import 'package:cashinator/repositories/payment_method_repository.dart';
import 'package:cashinator/repositories/product_repository.dart';
import 'package:cashinator/state/sample_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The draw is a held snapshot: it survives leaving the screen and only moves
/// when Draw again is asked for.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late AppDatabase database;
  late OrderRepository orders;
  late SampleController controller;
  late PaymentMethod cash;

  final day = DateTime(2026, 7, 20, 8);

  setUp(() async {
    database = await AppDatabase.open(fileName: inMemoryDatabasePath);
    orders = OrderRepository(database);
    controller = SampleController(orders);
    cash = (await PaymentMethodRepository(database).activeMethods())
        .firstWhere((method) => method.name == 'Cash');
  });

  tearDown(() async {
    await database.close();
  });

  Future<void> makeOrders(int count, {DateTime? on}) async {
    final catalogue = await ProductRepository(database).activeProducts();
    final start = on ?? day;
    for (var i = 0; i < count; i++) {
      await orders.createOrder(
        lines: [
          DraftLine(
            productId: catalogue.first.id,
            productName: catalogue.first.name,
            unitPrice: catalogue.first.price,
            qty: 1,
          ),
        ],
        paymentMethod: cash,
        now: start.add(Duration(minutes: i)),
      );
    }
  }

  Set<int?> idsOf(SampleView view) =>
      view.orders.map((entry) => entry.order.id).toSet();

  test('holds the same draw across repeated loads', () async {
    await makeOrders(40);

    final first = idsOf(await controller.load(day));
    for (var i = 0; i < 5; i++) {
      expect(idsOf(await controller.load(day)), equals(first));
    }
  });

  test('redraw moves the sample', () async {
    await makeOrders(40);

    final first = idsOf(await controller.load(day));
    var moved = false;
    for (var attempt = 0; attempt < 5 && !moved; attempt++) {
      moved = !idsOf(await controller.redraw(day)).containsAll(first);
    }
    expect(moved, isTrue);
  });

  test('a redraw is then held in its turn', () async {
    await makeOrders(40);

    await controller.load(day);
    final redrawn = idsOf(await controller.redraw(day));

    expect(idsOf(await controller.load(day)), equals(redrawn));
  });

  test('later sales stay out of a held draw, and are counted', () async {
    await makeOrders(20);
    final held = await controller.load(day);
    expect(held.orders, hasLength(9));
    expect(held.ordersSinceDraw, 0);

    await makeOrders(4, on: day.add(const Duration(hours: 3)));

    final reopened = await controller.load(day);
    expect(idsOf(reopened), equals(idsOf(held)),
        reason: 'the snapshot must not grow on its own');
    expect(reopened.dayOrderCount, 24);
    expect(reopened.ordersSinceDraw, 4);

    // Draw again takes the whole day into account: 45% of 24 is 11.
    final fresh = await controller.redraw(day);
    expect(fresh.orders, hasLength(11));
    expect(fresh.ordersSinceDraw, 0);
  });

  test('each day holds its own draw', () async {
    final other = DateTime(2026, 7, 21, 8);
    await makeOrders(20);
    await makeOrders(20, on: other);

    final first = idsOf(await controller.load(day));
    final second = idsOf(await controller.load(other));

    expect(idsOf(await controller.load(day)), equals(first));
    expect(idsOf(await controller.load(other)), equals(second));
    expect(first.intersection(second), isEmpty,
        reason: 'different days share no orders');
  });

  test('an empty day holds nothing, so the first sale gets sampled', () async {
    final quiet = await controller.load(day);
    expect(quiet.orders, isEmpty);
    expect(controller.isHolding(day), isFalse);

    await makeOrders(3);

    final afterSales = await controller.load(day);
    expect(afterSales.orders, hasLength(1));
    expect(controller.isHolding(day), isTrue);
  });

  test('holding a draw writes nothing', () async {
    await makeOrders(20);
    final before = await orders.ordersForDate(day);
    final totalsBefore = await orders.totalsForDate(day);

    await controller.load(day);
    await controller.load(day);
    await controller.redraw(day);

    final after = await orders.ordersForDate(day);
    final totalsAfter = await orders.totalsForDate(day);

    expect(after.map((e) => e.order.id), equals(before.map((e) => e.order.id)));
    expect(
        after.map((e) => e.order.status), equals(before.map((e) => e.order.status)));
    expect(totalsAfter.orderCount, totalsBefore.orderCount);
    expect(totalsAfter.revenue, totalsBefore.revenue);
  });
}
