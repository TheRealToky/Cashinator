import 'dart:io';

import 'package:cashinator/data/db/app_database.dart';
import 'package:cashinator/repositories/expense_repository.dart';
import 'package:cashinator/repositories/export_repository.dart';
import 'package:cashinator/repositories/order_repository.dart';
import 'package:cashinator/repositories/production_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late AppDatabase database;
  late ExportRepository exportRepo;
  late Directory tempDir;

  setUp(() async {
    database = await AppDatabase.open(fileName: inMemoryDatabasePath);
    final orders = OrderRepository(database);
    final expenses = ExpenseRepository(database);
    final production = ProductionRepository(database);
    exportRepo = ExportRepository(orders, expenses, production);
    tempDir = await Directory.systemTemp.createTemp('cashinator_export_test_');
  });

  tearDown(() async {
    await database.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('ExportRepository naming and file helpers', () {
    test('names single-day and range sales files correctly', () {
      final day1 = DateTime(2026, 9, 9);
      final day2 = DateTime(2026, 9, 10);

      expect(
        exportRepo.salesFileName(from: day1, to: day1),
        'pastry_sales_2026-09-09.xlsx',
      );
      expect(
        exportRepo.salesFileName(from: day1, to: day2),
        'pastry_sales_2026-09-09_to_2026-09-10.xlsx',
      );
    });

    test('names single-day and range expenses files correctly', () {
      final day1 = DateTime(2026, 9, 9);
      final day2 = DateTime(2026, 9, 10);

      expect(
        exportRepo.expenseFileName(from: day1, to: day1),
        'pastry_expenses_2026-09-09.xlsx',
      );
      expect(
        exportRepo.expenseFileName(from: day1, to: day2),
        'pastry_expenses_2026-09-09_to_2026-09-10.xlsx',
      );
    });

    test('findExistingSalesExport and findExistingExpenseExport locate files',
        () async {
      final day = DateTime(2026, 9, 9);
      final notFoundSales = await exportRepo.findExistingSalesExport(
        from: day,
        to: day,
        directoryOverride: tempDir,
      );
      expect(notFoundSales, isNull);

      final salesFile = File(p.join(tempDir.path, 'pastry_sales_2026-09-09.xlsx'));
      await salesFile.writeAsString('mock content');

      final foundSales = await exportRepo.findExistingSalesExport(
        from: day,
        to: day,
        directoryOverride: tempDir,
      );
      expect(foundSales, isNotNull);
      expect(foundSales!.path, salesFile.path);

      final expenseFile =
          File(p.join(tempDir.path, 'pastry_expenses_2026-09-09.xlsx'));
      await expenseFile.writeAsString('mock content');

      final foundExpense = await exportRepo.findExistingExpenseExport(
        from: day,
        to: day,
        directoryOverride: tempDir,
      );
      expect(foundExpense, isNotNull);
      expect(foundExpense!.path, expenseFile.path);
    });

    test('listRecentExports returns .xlsx files sorted newest first', () async {
      final file1 = File(p.join(tempDir.path, 'pastry_sales_2026-09-01.xlsx'));
      await file1.writeAsString('1');
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final file2 = File(p.join(tempDir.path, 'pastry_sales_2026-09-02.xlsx'));
      await file2.writeAsString('2');
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final notXlsx = File(p.join(tempDir.path, 'other.txt'));
      await notXlsx.writeAsString('3');

      final recent = await exportRepo.listRecentExports(
        directoryOverride: tempDir,
        limit: 5,
      );

      expect(recent, hasLength(2));
      expect(p.basename(recent.first.path), 'pastry_sales_2026-09-02.xlsx');
      expect(p.basename(recent.last.path), 'pastry_sales_2026-09-01.xlsx');
    });
  });
}
