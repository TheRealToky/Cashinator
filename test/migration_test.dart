import 'dart:io';

import 'package:cashinator/data/db/app_database.dart';
import 'package:cashinator/data/db/schema.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  test('Upgrading a v4 database to v5 preserves all existing data and creates unsold_logs table', () async {
    final tempDir = await Directory.systemTemp.createTemp('migration_test_');
    addTearDown(() => tempDir.delete(recursive: true));
    final dbPath = p.join(tempDir.path, 'upgrade_test.db');

    // 1. Create a database at v4.
    final db = await openDatabase(
      dbPath,
      version: 4,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        final batch = db.batch();
        for (final statement in kCreateStatements) {
          batch.execute(statement);
        }
        for (final statement in kCreateExpenseStatements) {
          batch.execute(statement);
        }
        for (final statement in kCreateProductionStatements) {
          batch.execute(statement);
        }
        await batch.commit(noResult: true);

        // Seed some data like a real live device would have.
        await db.insert('payment_methods', {'name': 'Cash', 'active': 1, 'sort_order': 0});
        await db.insert('products', {'name': 'Croissant', 'price': 3000, 'category': 'Pastries', 'active': 1, 'sort_order': 0});
        
        final staffPin = hashPin('1234');
        await db.insert('app_users', {
          'role': 'staff',
          'pin_hash': staffPin.hash,
          'pin_salt': staffPin.salt,
        });

        await db.insert('orders', {
          'id': 1,
          'order_label': '1',
          'business_date': '2026-09-25',
          'created_at': '2026-09-25T10:00:00.000',
          'payment_method_name': 'Cash',
          'status': 'normal',
          'total': 3000,
        });

        await db.insert('order_lines', {
          'order_id': 1,
          'product_name': 'Croissant',
          'qty': 1,
          'unit_price': 3000,
          'line_total': 3000,
        });

        await db.insert('expenses', {
          'name': 'Milk',
          'amount': 1500,
          'business_date': '2026-09-25',
          'created_at': '2026-09-25T11:00:00.000',
          'payment_method_name': 'Cash',
          'status': 'normal',
        });

        await db.insert('production_logs', {
          'product_name': 'Croissant',
          'unit_price': 3000,
          'qty': 20,
          'business_date': '2026-09-25',
          'recorded_at': '2026-09-25T07:00:00.000',
        });
      },
    );

    // Verify v4 contents before migration.
    final ordersV4 = await db.query('orders');
    final expensesV4 = await db.query('expenses');
    final productionV4 = await db.query('production_logs');
    expect(ordersV4, hasLength(1));
    expect(expensesV4, hasLength(1));
    expect(productionV4, hasLength(1));
    await db.close();

    // 2. Open via AppDatabase.open, which runs the migration to v5 (kSchemaVersion).
    final appDb = await AppDatabase.open(
      fileName: 'upgrade_test.db',
      directoryOverride: tempDir.path,
    );
    final migratedDb = appDb.db;

    // 3. Verify that all existing records are intact.
    final ordersMigrated = await migratedDb.query('orders');
    expect(ordersMigrated, hasLength(1));
    expect(ordersMigrated.first['order_label'], '1');
    expect(ordersMigrated.first['total'], 3000);

    final linesMigrated = await migratedDb.query('order_lines');
    expect(linesMigrated, hasLength(1));
    expect(linesMigrated.first['product_name'], 'Croissant');

    final expensesMigrated = await migratedDb.query('expenses');
    expect(expensesMigrated, hasLength(1));
    expect(expensesMigrated.first['name'], 'Milk');

    final productionMigrated = await migratedDb.query('production_logs');
    expect(productionMigrated, hasLength(1));
    expect(productionMigrated.first['qty'], 20);

    // 4. Verify that the new unsold_logs table is ready and writable.
    await migratedDb.insert('unsold_logs', {
      'product_name': 'Croissant',
      'unit_price': 3000,
      'qty': 5,
      'business_date': '2026-09-25',
      'recorded_at': '2026-09-25T18:00:00.000',
    });

    final unsoldMigrated = await migratedDb.query('unsold_logs');
    expect(unsoldMigrated, hasLength(1));
    expect(unsoldMigrated.first['qty'], 5);

    await appDb.close();
  });
}
