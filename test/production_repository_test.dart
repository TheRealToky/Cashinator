import 'package:cashinator/core/app_date.dart';
import 'package:cashinator/data/db/app_database.dart';
import 'package:cashinator/data/models/production_log.dart';
import 'package:cashinator/repositories/product_repository.dart';
import 'package:cashinator/repositories/production_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late AppDatabase database;
  late ProductionRepository productions;
  late ProductRepository productsRepo;

  setUp(() async {
    database = await AppDatabase.open(fileName: inMemoryDatabasePath);
    productions = ProductionRepository(database);
    productsRepo = ProductRepository(database);
  });

  tearDown(() async {
    await database.close();
  });

  group('ProductionRepository', () {
    test('recordSession records production items and creates log entries', () async {
      final products = await productsRepo.allProducts();
      expect(products, isNotEmpty);
      final p1 = products[0];
      final p2 = products[1];
      final now = DateTime.now();

      await productions.recordSession([
        ProductionLog(
          id: null,
          productId: p1.id,
          productName: p1.name,
          category: p1.category,
          unitPrice: p1.price,
          qty: 15,
          businessDate: formatIsoDate(now),
          recordedAt: now,
        ),
        ProductionLog(
          id: null,
          productId: p2.id,
          productName: p2.name,
          category: p2.category,
          unitPrice: p2.price,
          qty: 25,
          businessDate: formatIsoDate(now),
          recordedAt: now,
        ),
      ]);

      final forToday = await productions.logsForDate(now);
      expect(forToday, hasLength(2));
      expect(forToday.any((l) => l.productId == p1.id && l.qty == 15), isTrue);
      expect(forToday.any((l) => l.productId == p2.id && l.qty == 25), isTrue);
    });

    test('recordSession throws exception when all quantities are zero', () async {
      final products = await productsRepo.allProducts();
      final p1 = products[0];
      final now = DateTime.now();

      expect(
        () => productions.recordSession([
          ProductionLog(
            id: null,
            productId: p1.id,
            productName: p1.name,
            category: p1.category,
            unitPrice: p1.price,
            qty: 0,
            businessDate: formatIsoDate(now),
            recordedAt: now,
          ),
        ]),
        throwsException,
      );
    });

    test('totalsForDate aggregates correctly', () async {
      final products = await productsRepo.allProducts();
      final p1 = products[0];
      final p2 = products[1];
      final targetDate = DateTime(2026, 7, 10, 8, 30);
      final iso = formatIsoDate(targetDate);

      await productions.recordSession([
        ProductionLog(
          id: null,
          productId: p1.id,
          productName: p1.name,
          category: p1.category,
          unitPrice: 1000,
          qty: 10,
          businessDate: iso,
          recordedAt: targetDate,
        ),
        ProductionLog(
          id: null,
          productId: p2.id,
          productName: p2.name,
          category: p2.category,
          unitPrice: 2000,
          qty: 5,
          businessDate: iso,
          recordedAt: targetDate,
        ),
      ]);

      final totals = await productions.totalsForDate(targetDate);
      expect(totals.itemCount, 2);
      expect(totals.totalQty, 15);
      expect(totals.totalValue, 1000 * 10 + 2000 * 5); // 20000
    });

    test('logsInRange fetches entries within range', () async {
      final products = await productsRepo.allProducts();
      final p1 = products[0];
      final date1 = DateTime(2026, 6, 1, 7, 0);
      final date2 = DateTime(2026, 6, 2, 7, 0);
      final date3 = DateTime(2026, 6, 5, 7, 0);

      await productions.recordSession([
        ProductionLog(
          id: null,
          productId: p1.id,
          productName: p1.name,
          category: p1.category,
          unitPrice: 1000,
          qty: 10,
          businessDate: formatIsoDate(date1),
          recordedAt: date1,
        ),
      ]);
      await productions.recordSession([
        ProductionLog(
          id: null,
          productId: p1.id,
          productName: p1.name,
          category: p1.category,
          unitPrice: 1000,
          qty: 20,
          businessDate: formatIsoDate(date2),
          recordedAt: date2,
        ),
      ]);
      await productions.recordSession([
        ProductionLog(
          id: null,
          productId: p1.id,
          productName: p1.name,
          category: p1.category,
          unitPrice: 1000,
          qty: 30,
          businessDate: formatIsoDate(date3),
          recordedAt: date3,
        ),
      ]);

      final inRange = await productions.logsInRange(
        from: DateTime(2026, 6, 1),
        to: DateTime(2026, 6, 2),
      );

      expect(inRange, hasLength(2));
      expect(inRange[0].businessDate, '2026-06-01');
      expect(inRange[1].businessDate, '2026-06-02');
    });
  });
}
