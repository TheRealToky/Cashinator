import 'package:cashinator/data/db/app_database.dart';
import 'package:cashinator/repositories/order_repository.dart';
import 'package:cashinator/repositories/payment_method_repository.dart';
import 'package:cashinator/repositories/product_repository.dart';
import 'package:cashinator/state/sample_controller.dart';
import 'package:cashinator/ui/backoffice/order_views.dart';
import 'package:cashinator/ui/backoffice/sample_screen.dart';
import 'package:cashinator/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The Sample screen is a reading tool on live shop data, so these tests hold
/// it to two things: it shows a 45% slice of the day, and it offers no way to
/// change anything.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    // See pos_flow_test: the isolate factory deadlocks under the fake clock.
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  late AppDatabase database;
  late OrderRepository orders;
  late SampleController samples;

  setUp(() async {
    database = await AppDatabase.open(fileName: inMemoryDatabasePath);
    orders = OrderRepository(database);
    samples = SampleController(orders);
  });

  tearDown(() async {
    await database.close();
  });

  Future<void> makeTodaysOrders(int count) async {
    final catalogue = await ProductRepository(database).activeProducts();
    final cash = (await PaymentMethodRepository(database).activeMethods())
        .firstWhere((method) => method.name == 'Cash');

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
      );
    }
  }

  Widget wrap({Widget home = const SampleScreen()}) => MultiProvider(
        providers: [
          Provider<OrderRepository>.value(value: orders),
          Provider<SampleController>.value(value: samples),
        ],
        child: MaterialApp(theme: AppTheme.light(), home: home),
      );

  /// A stand-in for the back office: a tile that pushes Sample, so the screen
  /// can be left and reopened the way it is on the tablet.
  Widget host() => wrap(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const SampleScreen()),
                ),
                child: const Text('Open sample'),
              ),
            ),
          ),
        ),
      );

  List<int?> visibleOrderIds(WidgetTester tester) => tester
      .widgetList<OrderTile>(find.byType(OrderTile))
      .map((tile) => tile.entry.order.id)
      .toList();

  testWidgets('shows a 45% slice of today and says what it sampled', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(2560, 1600);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    await makeTodaysOrders(10);

    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    expect(find.byType(OrderTile), findsNWidgets(5));
    expect(find.textContaining('5 of 10 orders'), findsOneWidget);
    expect(find.textContaining('random 45%'), findsOneWidget);
  });

  testWidgets('the same draw is waiting when the page is reopened', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(2560, 1600);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    await makeTodaysOrders(10);
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open sample'));
    await tester.pumpAndSettle();
    final firstVisit = visibleOrderIds(tester);
    expect(firstVisit, hasLength(5));

    // Leave the page and come back, twice.
    for (var visit = 0; visit < 2; visit++) {
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('Open sample'), findsOneWidget);

      await tester.tap(find.text('Open sample'));
      await tester.pumpAndSettle();
      expect(visibleOrderIds(tester), equals(firstVisit));
    }
  });

  testWidgets('Draw again is what moves the sample', (tester) async {
    tester.view.physicalSize = const Size(2560, 1600);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    // 18 of 40 drawn: two identical draws in a row are a ~1-in-10^11 event.
    await makeTodaysOrders(40);
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    final before = (await samples.load(DateTime.now()))
        .orders
        .map((entry) => entry.order.id)
        .toSet();

    await tester.tap(find.text('Draw again'));
    await tester.pumpAndSettle();

    final after = (await samples.load(DateTime.now()))
        .orders
        .map((entry) => entry.order.id)
        .toSet();

    expect(after, isNot(equals(before)));
    expect(after, hasLength(18));
  });

  testWidgets('says how many sales arrived after the draw', (tester) async {
    tester.view.physicalSize = const Size(2560, 1600);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    await makeTodaysOrders(10);
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open sample'));
    await tester.pumpAndSettle();
    final held = visibleOrderIds(tester);
    expect(find.textContaining('since this draw'), findsNothing);

    // The till keeps selling while the draw is held.
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await makeTodaysOrders(2);
    await tester.tap(find.text('Open sample'));
    await tester.pumpAndSettle();

    expect(visibleOrderIds(tester), equals(held));
    expect(find.textContaining('5 of 12 orders'), findsOneWidget);
    expect(find.textContaining('2 sales rung up since this draw'),
        findsOneWidget);
  });

  testWidgets('offers no way to change an order, and changes none', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(2560, 1600);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    await makeTodaysOrders(10);
    final before = await orders.ordersForDate(DateTime.now());

    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    // Open a sampled order: the lines are readable, the void button is not
    // there to be tapped even off-screen.
    await tester.tap(find.byType(OrderTile).first);
    await tester.pumpAndSettle();
    expect(find.text('Void this order', skipOffstage: false), findsNothing);

    // Redraw a few times, the way a manager flicking through would.
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.text('Draw again'));
      await tester.pumpAndSettle();
    }

    final after = await orders.ordersForDate(DateTime.now());
    expect(after.map((entry) => entry.order.id),
        equals(before.map((entry) => entry.order.id)));
    expect(after.map((entry) => entry.order.status),
        equals(before.map((entry) => entry.order.status)));
    expect(after.map((entry) => entry.lines.length),
        equals(before.map((entry) => entry.lines.length)));
  });
}
