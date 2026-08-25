import 'dart:io';

import 'package:cashinator/core/app_date.dart';
import 'package:cashinator/core/app_exception.dart';
import 'package:cashinator/data/db/app_database.dart';
import 'package:cashinator/data/db/schema.dart';
import 'package:cashinator/data/models/expense.dart';
import 'package:cashinator/data/models/payment_method.dart';
import 'package:cashinator/repositories/expense_repository.dart';
import 'package:cashinator/repositories/order_repository.dart';
import 'package:cashinator/repositories/payment_method_repository.dart';
import 'package:cashinator/repositories/product_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Exercises expenses against the real schema in an in-memory SQLite database,
/// plus one test on a real file that upgrades a v2 database the way a tablet
/// already holding sales will be upgraded.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late AppDatabase database;
  late ExpenseRepository expenses;
  late PaymentMethod cash;
  late PaymentMethod momo;

  setUp(() async {
    database = await AppDatabase.open(fileName: inMemoryDatabasePath);
    expenses = ExpenseRepository(database);
    final methods = await PaymentMethodRepository(database).activeMethods();
    cash = methods.firstWhere((m) => m.name == 'Cash');
    momo = methods.firstWhere((m) => m.name == 'MoMo');
  });

  tearDown(() async {
    await database.close();
  });

  group('createExpense', () {
    test('records the expense against today', () async {
      final expense = await expenses.createExpense(
        name: 'Milk',
        amount: 12000,
        paymentMethod: cash,
      );

      expect(expense.id, isNotNull);
      expect(expense.amount, 12000);
      expect(expense.businessDate, formatIsoDate(DateTime.now()));
      expect(expense.status, ExpenseStatus.normal);

      final stored = await expenses.expensesForDate(DateTime.now());
      expect(stored, hasLength(1));
      expect(stored.single.name, 'Milk');
    });

    test('snapshots the payment method name', () async {
      final expense = await expenses.createExpense(
        name: 'Airtime',
        amount: 2000,
        paymentMethod: momo,
      );

      expect(expense.paymentMethodId, momo.id);
      expect(expense.paymentMethodName, 'MoMo');
    });

    test('stamps the moment it is given, so an expense can be backdated',
        () async {
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      final expense = await expenses.createExpense(
        name: 'Charcoal',
        amount: 8000,
        paymentMethod: cash,
        now: DateTime(yesterday.year, yesterday.month, yesterday.day, 16, 45),
      );

      expect(expense.businessDate, formatIsoDate(yesterday));
      expect(expense.timeLabel, '16:45');
      expect(await expenses.expensesForDate(DateTime.now()), isEmpty);
      expect(await expenses.expensesForDate(yesterday), hasLength(1));
    });

    test('trims the name and rejects an empty one', () async {
      final expense = await expenses.createExpense(
        name: '  Gas bottle  ',
        amount: 30000,
        paymentMethod: cash,
      );
      expect(expense.name, 'Gas bottle');

      expect(
        () => expenses.createExpense(
          name: '   ',
          amount: 500,
          paymentMethod: cash,
        ),
        throwsA(isA<ValidationException>()),
      );
    });

    test('rejects an amount of zero or less', () async {
      for (final amount in [0, -100]) {
        expect(
          () => expenses.createExpense(
            name: 'Nothing',
            amount: amount,
            paymentMethod: cash,
          ),
          throwsA(isA<ValidationException>()),
        );
      }
      expect(await expenses.expensesForDate(DateTime.now()), isEmpty);
    });
  });

  group('listing', () {
    test('returns a range in chronological order', () async {
      final today = startOfDay(DateTime.now());
      final yesterday = today.subtract(const Duration(days: 1));

      await expenses.createExpense(
        name: 'Second',
        amount: 200,
        paymentMethod: cash,
        now: today.add(const Duration(hours: 9)),
      );
      await expenses.createExpense(
        name: 'First',
        amount: 100,
        paymentMethod: cash,
        now: yesterday.add(const Duration(hours: 17)),
      );

      final range = await expenses.expensesInRange(from: yesterday, to: today);
      expect(range.map((e) => e.name), ['First', 'Second']);
    });

    test('refuses a backwards range', () async {
      final today = startOfDay(DateTime.now());
      expect(
        () => expenses.expensesInRange(
          from: today,
          to: today.subtract(const Duration(days: 2)),
        ),
        throwsA(isA<ValidationException>()),
      );
    });
  });

  group('voidExpense', () {
    test('keeps the row and records the audit trail', () async {
      final expense = await expenses.createExpense(
        name: 'Wrong amount',
        amount: 99000,
        paymentMethod: cash,
      );

      final voided = await expenses.voidExpense(
        expenseId: expense.id!,
        reason: 'Typed 99000 instead of 9900',
      );

      expect(voided.isVoided, isTrue);
      expect(voided.voidReason, 'Typed 99000 instead of 9900');
      expect(voided.voidedAt, isNotNull);

      // The row is still there — voiding is never a delete.
      final stored = await expenses.expensesForDate(DateTime.now());
      expect(stored, hasLength(1));
      expect(stored.single.status, ExpenseStatus.voided);
      expect(stored.single.amount, 99000);
    });

    test('needs a reason, and refuses to void twice', () async {
      final expense = await expenses.createExpense(
        name: 'Sugar',
        amount: 5000,
        paymentMethod: cash,
      );

      expect(
        () => expenses.voidExpense(expenseId: expense.id!, reason: '  '),
        throwsA(isA<ValidationException>()),
      );

      await expenses.voidExpense(expenseId: expense.id!, reason: 'Duplicate');
      expect(
        () => expenses.voidExpense(expenseId: expense.id!, reason: 'Again'),
        throwsA(isA<ConflictException>()),
      );
    });

    test('reports a missing expense rather than silently doing nothing', () {
      expect(
        () => expenses.voidExpense(expenseId: 4242, reason: 'Gone'),
        throwsA(isA<NotFoundException>()),
      );
    });
  });

  group('totalsForDate', () {
    test('sums the day and leaves voided expenses out', () async {
      await expenses.createExpense(
        name: 'Flour',
        amount: 20000,
        paymentMethod: cash,
      );
      await expenses.createExpense(
        name: 'Butter',
        amount: 15000,
        paymentMethod: momo,
      );
      final mistake = await expenses.createExpense(
        name: 'Mistake',
        amount: 500000,
        paymentMethod: cash,
      );
      await expenses.voidExpense(
        expenseId: mistake.id!,
        reason: 'Never happened',
      );

      final totals = await expenses.totalsForDate(DateTime.now());
      expect(totals.spend, 35000);
      expect(totals.expenseCount, 2);
      expect(totals.voidedCount, 1);
    });

    test('a day with nothing recorded reads as zero, not as an error',
        () async {
      final totals = await expenses.totalsForDate(
        DateTime.now().subtract(const Duration(days: 400)),
      );
      expect(totals.spend, 0);
      expect(totals.expenseCount, 0);
    });
  });

  // The feature ships onto a tablet that already holds months of real sales,
  // so the upgrade path matters more than any single query above.
  group('upgrading a v2 database', () {
    late Directory directory;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('cashinator_v2_');
    });

    tearDown(() async {
      if (directory.existsSync()) {
        await directory.delete(recursive: true);
      }
    });

    /// Builds the database exactly as schema v2 left it: every table this app
    /// shipped before expenses existed, and no `expenses` table.
    Future<void> createV2Database(String path) async {
      final db = await databaseFactory.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 2,
          onCreate: (db, version) async {
            var batch = db.batch();
            for (final statement in kCreateStatements) {
              batch.execute(statement);
            }
            await batch.commit(noResult: true);

            batch = db.batch();
            for (final method in kSeedPaymentMethods) {
              batch.insert('payment_methods', method);
            }
            batch.insert('products', {
              'name': 'Croissant',
              'price': 3000,
              'category': 'Pastries',
              'active': 1,
              'sort_order': 0,
            });
            batch.insert('app_users', {
              'role': 'manager',
              'pin_hash': 'hash',
              'pin_salt': 'salt',
            });
            await batch.commit(noResult: true);

            // One real sale, so the upgrade has something to lose.
            final orderId = await db.insert('orders', {
              'order_label': '1',
              'business_date': '2026-08-01',
              'created_at': '2026-08-01T09:15:00.000',
              'payment_method_id': 1,
              'payment_method_name': 'Cash',
              'status': 'normal',
              'total': 6000,
            });
            await db.insert('order_lines', {
              'order_id': orderId,
              'product_id': 1,
              'product_name': 'Croissant',
              'qty': 2,
              'unit_price': 3000,
              'line_total': 6000,
              'line_no': 0,
            });
          },
        ),
      );
      await db.close();
    }

    test('adds expenses without disturbing a single existing row', () async {
      const fileName = 'cashinator.db';
      await createV2Database('${directory.path}/$fileName');

      final upgraded = await AppDatabase.open(
        fileName: fileName,
        directoryOverride: directory.path,
      );
      addTearDown(upgraded.close);

      expect(await upgraded.db.getVersion(), kSchemaVersion);

      // The sale, its line, the catalogue, the methods and the PIN all survive.
      final orders = await OrderRepository(upgraded)
          .ordersInRange(from: DateTime(2026, 8, 1), to: DateTime(2026, 8, 1));
      expect(orders, hasLength(1));
      expect(orders.single.order.total, 6000);
      expect(orders.single.lines.single.productName, 'Croissant');

      expect(await ProductRepository(upgraded).allProducts(), hasLength(1));
      expect(
        (await PaymentMethodRepository(upgraded).activeMethods()).length,
        kSeedPaymentMethods.length,
      );

      final users = await upgraded.db.query('app_users');
      expect(users, hasLength(1));
      expect(users.single['pin_hash'], 'hash');

      // And the new table is there, empty, and usable.
      final repository = ExpenseRepository(upgraded);
      expect(await repository.expensesForDate(DateTime(2026, 8, 1)), isEmpty);

      final method = (await PaymentMethodRepository(upgraded).activeMethods())
          .firstWhere((m) => m.name == 'Cash');
      final expense = await repository.createExpense(
        name: 'Milk',
        amount: 3000,
        paymentMethod: method,
      );
      expect(expense.id, isNotNull);
    });

    test('re-running the v3 statements is harmless', () async {
      const fileName = 'cashinator.db';
      await createV2Database('${directory.path}/$fileName');

      final upgraded = await AppDatabase.open(
        fileName: fileName,
        directoryOverride: directory.path,
      );
      addTearDown(upgraded.close);

      final method = (await PaymentMethodRepository(upgraded).activeMethods())
          .firstWhere((m) => m.name == 'Cash');
      await ExpenseRepository(upgraded).createExpense(
        name: 'Milk',
        amount: 3000,
        paymentMethod: method,
      );

      // A migration interrupted part way is retried on the next launch. The
      // IF NOT EXISTS guards mean that neither fails nor drops what is there.
      for (final statement in kCreateExpenseStatements) {
        await upgraded.db.execute(statement);
      }

      expect(
        await ExpenseRepository(upgraded).expensesForDate(DateTime.now()),
        hasLength(1),
      );
    });
  });
}
