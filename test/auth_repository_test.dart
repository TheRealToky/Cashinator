import 'dart:io';

import 'package:cashinator/data/db/app_database.dart';
import 'package:cashinator/data/db/schema.dart';
import 'package:cashinator/repositories/auth_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Covers the three-role model: routing by PIN, the per-role capabilities the
/// back office gates its tools on, and the v1 -> v2 migration that adds the
/// limited `supervisor` role to a database that shipped with only two.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('roles and PINs on a fresh database', () {
    late AppDatabase database;
    late AuthRepository auth;

    setUp(() async {
      database = await AppDatabase.open(fileName: inMemoryDatabasePath);
      auth = AuthRepository(database);
    });

    tearDown(() async {
      await database.close();
    });

    test('each shipped default PIN routes to its own role', () async {
      expect(AppDatabase.defaultSupervisorPin, '9876');
      expect(
        await auth.authenticate(AppDatabase.defaultStaffPin),
        UserRole.staff,
      );
      expect(
        await auth.authenticate(AppDatabase.defaultManagerPin),
        UserRole.manager,
      );
      expect(
        await auth.authenticate(AppDatabase.defaultSupervisorPin),
        UserRole.supervisor,
      );
      expect(await auth.authenticate('0000'), isNull);
    });

    test('the supervisor starts on its default PIN', () async {
      expect(await auth.isUsingDefaultPin(UserRole.supervisor), isTrue);
    });

    test('changing the supervisor PIN rebinds auth and clears the default flag',
        () async {
      await auth.changePin(role: UserRole.supervisor, newPin: '246810');

      expect(await auth.isUsingDefaultPin(UserRole.supervisor), isFalse);
      expect(await auth.authenticate('9876'), isNull);
      expect(await auth.authenticate('246810'), UserRole.supervisor);
      // The other roles keep their PINs.
      expect(
        await auth.authenticate(AppDatabase.defaultManagerPin),
        UserRole.manager,
      );
    });
  });

  group('role capabilities', () {
    test('supervisor may view/void orders and export, nothing else', () {
      const supervisor = UserRole.supervisor;
      expect(supervisor.isBackOffice, isTrue);
      expect(supervisor.canManageOrders, isTrue);
      expect(supervisor.canExport, isTrue);
      expect(supervisor.canManageProducts, isFalse);
      expect(supervisor.canManagePaymentMethods, isFalse);
      expect(supervisor.canChangePins, isFalse);
    });

    test('manager may do everything in the back office', () {
      const manager = UserRole.manager;
      expect(manager.canManageOrders, isTrue);
      expect(manager.canExport, isTrue);
      expect(manager.canManageProducts, isTrue);
      expect(manager.canManagePaymentMethods, isTrue);
      expect(manager.canChangePins, isTrue);
    });

    test('front-office staff never reaches the back office', () {
      const staff = UserRole.staff;
      expect(staff.isBackOffice, isFalse);
      expect(staff.canManageOrders, isFalse);
      expect(staff.canExport, isFalse);
      expect(staff.canManageProducts, isFalse);
      expect(staff.canManagePaymentMethods, isFalse);
      expect(staff.canChangePins, isFalse);
    });
  });

  group('upgrading a v1 database', () {
    test('adds the supervisor on 9876 without disturbing existing PINs',
        () async {
      final dir = await Directory.systemTemp.createTemp('cashinator_migration');
      addTearDown(() async {
        try {
          await dir.delete(recursive: true);
        } catch (_) {
          // Best effort: a locked temp file must not fail the test.
        }
      });

      const fileName = 'legacy.db';
      final path = p.join(dir.path, fileName);

      // Recreate app_users exactly as v1 shipped it: two roles, no supervisor.
      final legacy = await databaseFactory.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, _) async {
            await db.execute('''
              CREATE TABLE app_users (
                id        INTEGER PRIMARY KEY AUTOINCREMENT,
                role      TEXT    NOT NULL UNIQUE
                          CHECK (role IN ('staff', 'manager')),
                pin_hash  TEXT    NOT NULL,
                pin_salt  TEXT    NOT NULL
              )
            ''');
            final staff = hashPin(AppDatabase.defaultStaffPin);
            final manager = hashPin(AppDatabase.defaultManagerPin);
            await db.insert('app_users', {
              'role': 'staff',
              'pin_hash': staff.hash,
              'pin_salt': staff.salt,
            });
            await db.insert('app_users', {
              'role': 'manager',
              'pin_hash': manager.hash,
              'pin_salt': manager.salt,
            });
          },
        ),
      );
      await legacy.close();

      // Reopening through AppDatabase runs the real v2 migration.
      final upgraded = await AppDatabase.open(
        fileName: fileName,
        directoryOverride: dir.path,
      );
      addTearDown(() async => upgraded.close());
      final auth = AuthRepository(upgraded);

      expect(await auth.authenticate('9876'), UserRole.supervisor);
      expect(
        await auth.authenticate(AppDatabase.defaultStaffPin),
        UserRole.staff,
      );
      expect(
        await auth.authenticate(AppDatabase.defaultManagerPin),
        UserRole.manager,
      );
      expect(await auth.isUsingDefaultPin(UserRole.supervisor), isTrue);
    });

    test('preserves every product, payment method and order row', () async {
      final dir = await Directory.systemTemp.createTemp('cashinator_dataloss');
      addTearDown(() async {
        try {
          await dir.delete(recursive: true);
        } catch (_) {
          // Best effort.
        }
      });

      const fileName = 'shop.db';
      final path = p.join(dir.path, fileName);

      // v1 differed from v2 in exactly one thing — the app_users role CHECK —
      // so reuse the real definitions of every other table and swap only that
      // one statement. This is a faithful pre-upgrade database, not a mock.
      const v1AppUsers = '''
        CREATE TABLE app_users (
          id        INTEGER PRIMARY KEY AUTOINCREMENT,
          role      TEXT    NOT NULL UNIQUE CHECK (role IN ('staff', 'manager')),
          pin_hash  TEXT    NOT NULL,
          pin_salt  TEXT    NOT NULL
        )
      ''';
      final v1Statements = [
        for (final statement in kCreateStatements)
          statement.contains('CREATE TABLE app_users')
              ? v1AppUsers
              : statement,
      ];

      final legacy = await databaseFactory.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, _) async {
            for (final statement in v1Statements) {
              await db.execute(statement);
            }
            // A day's worth of real data across the tables the migration must
            // not touch: two payment methods, two products, one 2-line order.
            await db.insert('payment_methods',
                {'name': 'Cash', 'active': 1, 'sort_order': 0});
            await db.insert('payment_methods',
                {'name': 'MoMo', 'active': 1, 'sort_order': 1});
            await db.insert('products', {
              'name': 'Croissant',
              'price': 3000,
              'category': 'Pastries',
              'active': 1,
              'sort_order': 0,
            });
            await db.insert('products', {
              'name': 'Espresso',
              'price': 2500,
              'category': 'Coffees',
              'active': 1,
              'sort_order': 1,
            });
            await db.insert('orders', {
              'order_label': '001',
              'business_date': '2026-07-20',
              'created_at': '2026-07-20T08:30:00.000',
              'payment_method_id': 1,
              'payment_method_name': 'Cash',
              'status': 'normal',
              'total': 8500,
            });
            await db.insert('order_lines', {
              'order_id': 1,
              'product_id': 1,
              'product_name': 'Croissant',
              'qty': 2,
              'unit_price': 3000,
              'line_total': 6000,
              'line_no': 1,
            });
            await db.insert('order_lines', {
              'order_id': 1,
              'product_id': 2,
              'product_name': 'Espresso',
              'qty': 1,
              'unit_price': 2500,
              'line_total': 2500,
              'line_no': 2,
            });

            final staff = hashPin(AppDatabase.defaultStaffPin);
            final manager = hashPin(AppDatabase.defaultManagerPin);
            await db.insert('app_users', {
              'role': 'staff',
              'pin_hash': staff.hash,
              'pin_salt': staff.salt,
            });
            await db.insert('app_users', {
              'role': 'manager',
              'pin_hash': manager.hash,
              'pin_salt': manager.salt,
            });
          },
        ),
      );
      await legacy.close();

      final upgraded = await AppDatabase.open(
        fileName: fileName,
        directoryOverride: dir.path,
      );
      addTearDown(() async => upgraded.close());

      // Every shop-data table survives byte-for-byte.
      final products = await upgraded.db.query('products', orderBy: 'id');
      expect(products, hasLength(2));
      expect(products[0]['name'], 'Croissant');
      expect(products[0]['price'], 3000);
      expect(products[1]['name'], 'Espresso');

      final methods = await upgraded.db.query('payment_methods', orderBy: 'id');
      expect(methods.map((m) => m['name']), ['Cash', 'MoMo']);

      final orders = await upgraded.db.query('orders');
      expect(orders, hasLength(1));
      expect(orders.first['order_label'], '001');
      expect(orders.first['total'], 8500);
      expect(orders.first['status'], 'normal');

      final lines = await upgraded.db.query('order_lines', orderBy: 'line_no');
      expect(lines, hasLength(2));
      expect(lines[0]['product_name'], 'Croissant');
      expect(lines[0]['qty'], 2);
      expect(lines[1]['product_name'], 'Espresso');

      // The existing PINs still work, and the supervisor has been added.
      final auth = AuthRepository(upgraded);
      expect(
        await auth.authenticate(AppDatabase.defaultStaffPin),
        UserRole.staff,
      );
      expect(
        await auth.authenticate(AppDatabase.defaultManagerPin),
        UserRole.manager,
      );
      expect(await auth.authenticate('9876'), UserRole.supervisor);
    });
  });
}
