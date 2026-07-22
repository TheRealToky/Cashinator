import 'package:cashinator/core/app_date.dart';
import 'package:cashinator/data/db/app_database.dart';
import 'package:cashinator/data/db/schema.dart';
import 'package:cashinator/repositories/order_repository.dart';
import 'package:cashinator/repositories/payment_method_repository.dart';
import 'package:cashinator/repositories/product_repository.dart';
import 'package:cashinator/state/cart_controller.dart';
import 'package:cashinator/state/catalog_controller.dart';
import 'package:cashinator/ui/pos/pos_screen.dart';
import 'package:cashinator/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Drives the till the way a cashier does, to keep the headline claim honest:
/// a one-item sale is three taps (product → Charge → payment method).
void main() {
  // The first tile on the grid, taken from the seed rather than hard-coded:
  // the catalogue is management's data and gets replaced wholesale, and only
  // the leading tiles are guaranteed to be laid out in a virtualised grid.
  final firstProduct = kSeedProducts.first['name']! as String;

  setUpAll(() {
    sqfliteFfiInit();
    // The no-isolate factory is essential inside testWidgets: the default
    // databaseFactoryFfi runs SQLite in a background isolate whose messaging
    // relies on real timers, but the widget-test binding fakes the clock, so
    // the isolate deadlocks and every DB read hangs ("database locked 10s").
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  late AppDatabase database;

  setUp(() async {
    database = await AppDatabase.open(fileName: inMemoryDatabasePath);
  });

  tearDown(() async {
    await database.close();
  });

  Widget wrap() {
    final products = ProductRepository(database);
    final methods = PaymentMethodRepository(database);

    return MultiProvider(
      providers: [
        Provider<ProductRepository>.value(value: products),
        Provider<PaymentMethodRepository>.value(value: methods),
        Provider<OrderRepository>(create: (_) => OrderRepository(database)),
        ChangeNotifierProvider<CartController>(create: (_) => CartController()),
        ChangeNotifierProvider<CatalogController>(
          create: (_) => CatalogController(
            products: products,
            paymentMethods: methods,
          ),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const PosScreen(),
      ),
    );
  }

  testWidgets('a one-item sale takes three taps and is recorded', (
    tester,
  ) async {
    // A tablet-sized surface, so the grid and cart panel both lay out.
    tester.view.physicalSize = const Size(2560, 1600);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    expect(find.text(firstProduct), findsOneWidget);
    expect(find.text('Tap a product to start a sale.'), findsOneWidget);

    // Tap 1: the product.
    await tester.tap(find.text(firstProduct).first);
    await tester.pumpAndSettle();

    expect(find.text('1 item'), findsOneWidget);

    // Tap 2: Charge.
    await tester.tap(find.widgetWithText(FilledButton, 'Charge'));
    await tester.pumpAndSettle();

    expect(find.text('How is the customer paying?'), findsOneWidget);

    // Tap 3: the payment method — which also confirms.
    await tester.tap(find.widgetWithText(FilledButton, 'Cash'));
    await tester.pumpAndSettle();

    // The cart resets for the next customer...
    expect(find.text('Tap a product to start a sale.'), findsOneWidget);

    // ...and the sale is in the database.
    final stored =
        await OrderRepository(database).ordersForDate(DateTime.now());
    expect(stored, hasLength(1));
    expect(stored.single.order.paymentMethodName, 'Cash');
    expect(stored.single.lines.single.productName, firstProduct);
    expect(stored.single.lines.single.qty, 1);
  });

  testWidgets('repeated taps on one product increment its quantity', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(2560, 1600);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    await tester.tap(find.text(firstProduct).first);
    await tester.tap(find.text(firstProduct).first);
    await tester.tap(find.text(firstProduct).first);
    await tester.pumpAndSettle();

    expect(find.text('3 items'), findsOneWidget);
  });

  testWidgets('a sale can be recorded at a time the cashier types', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(2560, 1600);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    // Any fixed target could coincide with the real clock, which the sheet
    // reads as "not edited"; this pair cannot both be the current hour.
    final target = DateTime.now().hour == 9
        ? const TimeOfDay(hour: 14, minute: 5)
        : const TimeOfDay(hour: 9, minute: 30);

    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    await tester.tap(find.text(firstProduct).first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Charge'));
    await tester.pumpAndSettle();

    // The sale defaults to the current time and says so.
    expect(find.text('Sale time'), findsOneWidget);
    expect(find.byIcon(Icons.restore), findsNothing);

    await tester.tap(find.text('Sale time'));
    await tester.pumpAndSettle();

    for (final key in _keystrokesFor(target)) {
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(OutlinedButton, key),
        ),
      );
      await tester.pumpAndSettle();
    }

    final label = '${_two(target.hour)}:${_two(target.minute)}';
    await tester.tap(find.widgetWithText(FilledButton, 'Set $label'));
    await tester.pumpAndSettle();

    // The edited time stays on screen through the payment step.
    expect(find.text('Sale time (edited)'), findsOneWidget);
    expect(find.text(label), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Cash'));
    await tester.pumpAndSettle();

    final stored =
        await OrderRepository(database).ordersForDate(DateTime.now());
    final order = stored.single.order;
    expect(order.timeLabel, label);
    // Only the clock moved: the sale still belongs to today's business date,
    // and so to today's order sequence and totals.
    expect(order.businessDate, formatIsoDate(DateTime.now()));
  });

  testWidgets('an edited sale time can be handed back to the clock', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(2560, 1600);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    await tester.tap(find.text(firstProduct).first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Charge'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sale time'));
    await tester.pumpAndSettle();

    // The nudge staff reach for when a sale is rung up well after the fact.
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.textContaining('30 min'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining(RegExp(r'^Set \d\d:\d\d$')));
    await tester.pumpAndSettle();

    expect(find.text('Sale time (edited)'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.restore));
    await tester.pumpAndSettle();

    expect(find.text('Sale time'), findsOneWidget);
    expect(find.byIcon(Icons.restore), findsNothing);

    await tester.tap(find.widgetWithText(FilledButton, 'Cash'));
    await tester.pumpAndSettle();

    final stored =
        await OrderRepository(database).ordersForDate(DateTime.now());
    expect(
      stored.single.order.createdAt.difference(DateTime.now()).abs(),
      lessThan(const Duration(minutes: 1)),
      reason: 'a reset sale is stamped by the clock, not by the nudge',
    );
  });

  testWidgets('the cart is not cleared when a sale is not confirmed', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(2560, 1600);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    await tester.tap(find.text(firstProduct).first);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Charge'));
    await tester.pumpAndSettle();

    // Back out of the payment sheet instead of choosing a method.
    await tester.tap(find.text('Back to the cart'));
    await tester.pumpAndSettle();

    expect(find.text('1 item'), findsOneWidget);

    final stored =
        await OrderRepository(database).ordersForDate(DateTime.now());
    expect(stored, isEmpty, reason: 'nothing is written until payment');
  });
}

String _two(int value) => value.toString().padLeft(2, '0');

/// The pad keys that spell [time], mirroring how entry auto-advances: an hour
/// of 3–9 cannot begin a two-digit hour, so it is typed as one key.
List<String> _keystrokesFor(TimeOfDay time) => [
      if (time.hour >= 3 && time.hour <= 9)
        '${time.hour}'
      else
        ..._two(time.hour).split(''),
      ..._two(time.minute).split(''),
    ];
