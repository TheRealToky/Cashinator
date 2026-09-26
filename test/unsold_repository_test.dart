import 'package:cashinator/core/app_date.dart';
import 'package:cashinator/data/db/app_database.dart';
import 'package:cashinator/data/models/unsold_log.dart';
import 'package:cashinator/repositories/product_repository.dart';
import 'package:cashinator/repositories/unsold_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late AppDatabase database;
  late UnsoldRepository unsoldRepo;
  late ProductRepository productsRepo;

  setUp(() async {
    database = await AppDatabase.open(fileName: inMemoryDatabasePath);
    unsoldRepo = UnsoldRepository(database);
    productsRepo = ProductRepository(database);
  });

  tearDown(() async {
    await database.close();
  });

  group('UnsoldRepository', () {
    test('recordSession records unsold items and creates log entries', () async {
      final products = await productsRepo.allProducts();
      expect(products, isNotEmpty);
      final p1 = products[0];
      final p2 = products[1];
      final now = DateTime.now();

      await unsoldRepo.recordSession([
        UnsoldLog(
          id: null,
          productId: p1.id,
          productName: p1.name,
          category: p1.category,
          unitPrice: p1.price,
          qty: 5,
          businessDate: formatIsoDate(now),
          recordedAt: now,
        ),
        UnsoldLog(
          id: null,
          productId: p2.id,
          productName: p2.name,
          category: p2.category,
          unitPrice: p2.price,
          qty: 8,
          businessDate: formatIsoDate(now),
          recordedAt: now,
        ),
      ]);

      final forToday = await unsoldRepo.logsForDate(now);
      expect(forToday, hasLength(2));
      expect(forToday.any((l) => l.productId == p1.id && l.qty == 5), isTrue);
      expect(forToday.any((l) => l.productId == p2.id && l.qty == 8), isTrue);
    });

    test('recordSession throws exception when all quantities are zero', () async {
      final products = await productsRepo.allProducts();
      final p1 = products[0];
      final now = DateTime.now();

      expect(
        () => unsoldRepo.recordSession([
          UnsoldLog(
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
      final targetDate = DateTime(2026, 7, 10, 18, 30);
      final iso = formatIsoDate(targetDate);

      await unsoldRepo.recordSession([
        UnsoldLog(
          id: null,
          productId: p1.id,
          productName: p1.name,
          category: p1.category,
          unitPrice: 1000,
          qty: 4,
          businessDate: iso,
          recordedAt: targetDate,
        ),
        UnsoldLog(
          id: null,
          productId: p2.id,
          productName: p2.name,
          category: p2.category,
          unitPrice: 2000,
          qty: 3,
          businessDate: iso,
          recordedAt: targetDate,
        ),
      ]);

      final totals = await unsoldRepo.totalsForDate(targetDate);
      expect(totals.itemCount, 2);
      expect(totals.totalQty, 7);
      expect(totals.totalValue, 1000 * 4 + 2000 * 3); // 10000
    });

    test('logsInRange fetches entries within range', () async {
      final products = await productsRepo.allProducts();
      final p1 = products[0];
      final date1 = DateTime(2026, 6, 1, 19, 0);
      final date2 = DateTime(2026, 6, 2, 19, 0);
      final date3 = DateTime(2026, 6, 5, 19, 0);

      await unsoldRepo.recordSession([
        UnsoldLog(
          id: null,
          productId: p1.id,
          productName: p1.name,
          category: p1.category,
          unitPrice: 1000,
          qty: 2,
          businessDate: formatIsoDate(date1),
          recordedAt: date1,
        ),
      ]);
      await unsoldRepo.recordSession([
        UnsoldLog(
          id: null,
          productId: p1.id,
          productName: p1.name,
          category: p1.category,
          unitPrice: 1000,
          qty: 6,
          businessDate: formatIsoDate(date2),
          recordedAt: date2,
        ),
      ]);
      await unsoldRepo.recordSession([
        UnsoldLog(
          id: null,
          productId: p1.id,
          productName: p1.name,
          category: p1.category,
          unitPrice: 1000,
          qty: 9,
          businessDate: formatIsoDate(date3),
          recordedAt: date3,
        ),
      ]);

      final inRange = await unsoldRepo.logsInRange(
        from: DateTime(2026, 6, 1),
        to: DateTime(2026, 6, 2),
      );

      expect(inRange, hasLength(2));
      expect(inRange[0].businessDate, '2026-06-01');
      expect(inRange[1].businessDate, '2026-06-02');
    });
  });
}
