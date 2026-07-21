import 'package:cashinator/core/app_exception.dart';
import 'package:cashinator/data/db/app_database.dart';
import 'package:cashinator/data/models/order.dart';
import 'package:cashinator/data/models/payment_method.dart';
import 'package:cashinator/data/models/product.dart';
import 'package:cashinator/repositories/order_repository.dart';
import 'package:cashinator/repositories/payment_method_repository.dart';
import 'package:cashinator/repositories/product_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Exercises the real schema against an in-memory SQLite database, so the
/// CHECK constraints and the transaction boundaries are covered rather than
/// mocked away.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late AppDatabase database;
  late OrderRepository orders;
  late ProductRepository products;
  late PaymentMethodRepository methods;
  late PaymentMethod cash;

  setUp(() async {
    database = await AppDatabase.open(fileName: inMemoryDatabasePath);
    orders = OrderRepository(database);
    products = ProductRepository(database);
    methods = PaymentMethodRepository(database);
    cash = (await methods.activeMethods()).firstWhere((m) => m.name == 'Cash');
  });

  tearDown(() async {
    await database.close();
  });

  group('seed data', () {
    test('ships the three payment methods the shop already uses', () async {
      final names = (await methods.activeMethods()).map((m) => m.name).toList();
      expect(names, containsAll(['Cash', 'MoMo', 'Card']));
    });

    test('ships a non-empty product catalogue', () async {
      expect(await products.activeProducts(), isNotEmpty);
    });
  });

  group('createOrder', () {
    test('writes the order and its lines together', () async {
      final catalogue = await products.activeProducts();
      final croissant = catalogue.first;

      final order = await orders.createOrder(
        lines: [
          DraftLine(
            productId: croissant.id,
            productName: croissant.name,
            unitPrice: croissant.price,
            qty: 3,
          ),
        ],
        paymentMethod: cash,
      );

      expect(order.id, isNotNull);
      expect(order.total, croissant.price * 3);
      expect(order.status, OrderStatus.normal);

      final stored = await orders.ordersForDate(DateTime.now());
      expect(stored, hasLength(1));
      expect(stored.single.lines, hasLength(1));
      expect(stored.single.lines.single.qty, 3);
    });

    test('snapshots the product name and price', () async {
      final catalogue = await products.activeProducts();
      final croissant = catalogue.first;
      final originalPrice = croissant.price;

      await orders.createOrder(
        lines: [
          DraftLine(
            productId: croissant.id,
            productName: croissant.name,
            unitPrice: originalPrice,
            qty: 1,
          ),
        ],
        paymentMethod: cash,
      );

      // The shop raises the price and renames the product afterwards.
      await products.update(
        croissant.copyWith(name: 'Croissant (large)', price: originalPrice + 5000),
      );

      final stored = await orders.ordersForDate(DateTime.now());
      final line = stored.single.lines.single;

      expect(line.unitPrice, originalPrice,
          reason: 'a later price change must not rewrite history');
      expect(line.productName, croissant.name);
    });

    test('snapshots the payment method name', () async {
      final catalogue = await products.activeProducts();

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

      await methods.update(cash.copyWith(name: 'Cash (till 2)'));

      final stored = await orders.ordersForDate(DateTime.now());
      expect(stored.single.order.paymentMethodName, 'Cash');
    });

    test('numbers orders per day starting at 1', () async {
      final catalogue = await products.activeProducts();
      DraftLine line() => DraftLine(
            productId: catalogue.first.id,
            productName: catalogue.first.name,
            unitPrice: catalogue.first.price,
            qty: 1,
          );

      final today = DateTime(2026, 7, 20, 9);
      final first = await orders.createOrder(
        lines: [line()],
        paymentMethod: cash,
        now: today,
      );
      final second = await orders.createOrder(
        lines: [line()],
        paymentMethod: cash,
        now: today.add(const Duration(minutes: 5)),
      );
      final nextDay = await orders.createOrder(
        lines: [line()],
        paymentMethod: cash,
        now: DateTime(2026, 7, 21, 9),
      );

      expect(first.orderLabel, '1');
      expect(second.orderLabel, '2');
      expect(nextDay.orderLabel, '1',
          reason: 'the label restarts each business day');
    });

    test('rejects an empty cart', () async {
      expect(
        () => orders.createOrder(lines: const [], paymentMethod: cash),
        throwsA(isA<ValidationException>()),
      );
    });

    test('rejects a zero quantity', () async {
      expect(
        () => orders.createOrder(
          lines: const [
            DraftLine(
              productId: 1,
              productName: 'Croissant',
              unitPrice: 3000,
              qty: 0,
            ),
          ],
          paymentMethod: cash,
        ),
        throwsA(isA<ValidationException>()),
      );
    });
  });

  group('voidOrder', () {
    Future<Order> makeOrder() async {
      final catalogue = await products.activeProducts();
      return orders.createOrder(
        lines: [
          DraftLine(
            productId: catalogue.first.id,
            productName: catalogue.first.name,
            unitPrice: catalogue.first.price,
            qty: 2,
          ),
        ],
        paymentMethod: cash,
      );
    }

    test('keeps the order and its lines, recording reason and time', () async {
      final order = await makeOrder();

      final voided = await orders.voidOrder(
        orderId: order.id!,
        reason: 'Customer changed their mind',
      );

      expect(voided.status, OrderStatus.voided);
      expect(voided.voidReason, 'Customer changed their mind');
      expect(voided.voidedAt, isNotNull);

      final stored = await orders.ordersForDate(DateTime.now());
      expect(stored, hasLength(1), reason: 'the order must not be deleted');
      expect(stored.single.lines, hasLength(1),
          reason: 'the lines must survive for the audit trail');
      expect(stored.single.order.isVoided, isTrue);
    });

    test('refuses an empty reason', () async {
      final order = await makeOrder();
      expect(
        () => orders.voidOrder(orderId: order.id!, reason: '   '),
        throwsA(isA<ValidationException>()),
      );
    });

    test('refuses to void twice', () async {
      final order = await makeOrder();
      await orders.voidOrder(orderId: order.id!, reason: 'First');

      expect(
        () => orders.voidOrder(orderId: order.id!, reason: 'Second'),
        throwsA(isA<ConflictException>()),
      );
    });

    test('reports a missing order', () async {
      expect(
        () => orders.voidOrder(orderId: 9999, reason: 'Nope'),
        throwsA(isA<NotFoundException>()),
      );
    });

    test('drops out of the day totals but stays countable as voided', () async {
      final order = await makeOrder();
      final before = await orders.totalsForDate(DateTime.now());
      expect(before.orderCount, 1);
      expect(before.revenue, greaterThan(0));

      await orders.voidOrder(orderId: order.id!, reason: 'Void it');

      final after = await orders.totalsForDate(DateTime.now());
      expect(after.orderCount, 0);
      expect(after.revenue, 0);
      expect(after.voidedCount, 1);
    });
  });

  group('ordersInRange', () {
    test('rejects an inverted range', () async {
      expect(
        () => orders.ordersInRange(
          from: DateTime(2026, 7, 20),
          to: DateTime(2026, 7, 10),
        ),
        throwsA(isA<ValidationException>()),
      );
    });

    test('returns an empty list rather than throwing on a quiet range', () async {
      final result = await orders.ordersInRange(
        from: DateTime(2020, 1, 1),
        to: DateTime(2020, 1, 31),
      );
      expect(result, isEmpty);
    });
  });

  group('payment methods', () {
    test('rejects a duplicate name regardless of case', () async {
      expect(
        () => methods.create(
          const PaymentMethod(id: null, name: 'momo', active: true),
        ),
        throwsA(isA<ValidationException>()),
        reason: 'the ledgers already suffer from a MoMo/Momo split',
      );
    });

    test('refuses to deactivate the last active method', () async {
      final all = await methods.activeMethods();
      for (final method in all.where((m) => m.id != cash.id)) {
        await methods.setActive(method.id!, active: false);
      }

      expect(
        () => methods.setActive(cash.id!, active: false),
        throwsA(isA<ConflictException>()),
      );
    });
  });

  group('products', () {
    test('deactivating hides from the till without deleting', () async {
      final catalogue = await products.activeProducts();
      final target = catalogue.first;

      await products.setActive(target.id!, active: false);

      final active = await products.activeProducts();
      final all = await products.allProducts();

      expect(active.map((p) => p.id), isNot(contains(target.id)));
      expect(all.map((p) => p.id), contains(target.id));
    });

    test('rejects an empty name', () async {
      expect(
        () => products.create(
          const Product(id: null, name: '  ', price: 100, active: true),
        ),
        throwsA(isA<ValidationException>()),
      );
    });

    test('rejects a negative price', () async {
      expect(
        () => products.create(
          const Product(id: null, name: 'Test', price: -1, active: true),
        ),
        throwsA(isA<ValidationException>()),
      );
    });
  });
}
