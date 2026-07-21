import 'package:cashinator/data/db/app_database.dart';
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

    expect(find.text('Croissant'), findsOneWidget);
    expect(find.text('Tap a product to start a sale.'), findsOneWidget);

    // Tap 1: the product.
    await tester.tap(find.text('Croissant').first);
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
    expect(stored.single.lines.single.productName, 'Croissant');
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

    await tester.tap(find.text('Croissant').first);
    await tester.tap(find.text('Croissant').first);
    await tester.tap(find.text('Croissant').first);
    await tester.pumpAndSettle();

    expect(find.text('3 items'), findsOneWidget);
  });

  testWidgets('the cart is not cleared when a sale is not confirmed', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(2560, 1600);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Croissant').first);
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
