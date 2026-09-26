import 'package:cashinator/core/app_date.dart';
import 'package:cashinator/data/db/app_database.dart';
import 'package:cashinator/data/models/production_log.dart';
import 'package:cashinator/data/models/unsold_log.dart';
import 'package:cashinator/repositories/product_repository.dart';
import 'package:cashinator/repositories/production_repository.dart';
import 'package:cashinator/repositories/unsold_repository.dart';
import 'package:cashinator/ui/backoffice/production_history_screen.dart';
import 'package:cashinator/ui/backoffice/unsold_history_screen.dart';
import 'package:cashinator/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  late AppDatabase database;
  late ProductRepository productRepo;
  late ProductionRepository productionRepo;
  late UnsoldRepository unsoldRepo;

  setUp(() async {
    database = await AppDatabase.open(fileName: inMemoryDatabasePath);
    productRepo = ProductRepository(database);
    productionRepo = ProductionRepository(database);
    unsoldRepo = UnsoldRepository(database);
  });

  tearDown(() async {
    await database.close();
  });

  Widget wrap(Widget home) => MultiProvider(
        providers: [
          Provider<ProductRepository>.value(value: productRepo),
          Provider<ProductionRepository>.value(value: productionRepo),
          Provider<UnsoldRepository>.value(value: unsoldRepo),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: home,
        ),
      );

  group('ProductionHistoryScreen', () {
    testWidgets('shows empty state when no production exists for date',
        (tester) async {
      tester.view.physicalSize = const Size(2560, 1600);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(wrap(const ProductionHistoryScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Production history'), findsOneWidget);
      expect(find.text('No production recorded on this day.'), findsOneWidget);
    });

    testWidgets('shows sessions and expands to show product lines',
        (tester) async {
      tester.view.physicalSize = const Size(2560, 1600);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);

      final products = await productRepo.allProducts();
      final p1 = products[0];
      final p2 = products[1];
      final now = DateTime.now();

      await productionRepo.recordSession([
        ProductionLog(
          id: null,
          productId: p1.id,
          productName: p1.name,
          category: p1.category,
          unitPrice: p1.price,
          qty: 12,
          businessDate: formatIsoDate(now),
          recordedAt: now,
        ),
        ProductionLog(
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

      await tester.pumpWidget(wrap(const ProductionHistoryScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Production history'), findsOneWidget);
      expect(find.textContaining('Total: 20 units produced'), findsOneWidget);
      expect(find.text('Session at ${formatHourMinute(now)}'), findsOneWidget);

      // Tap to expand session.
      await tester.tap(find.text('Session at ${formatHourMinute(now)}'));
      await tester.pumpAndSettle();

      expect(find.text('12×'), findsOneWidget);
      expect(find.text(p1.name), findsOneWidget);
      expect(find.text('8×'), findsOneWidget);
      expect(find.text(p2.name), findsOneWidget);
    });
  });

  group('UnsoldHistoryScreen', () {
    testWidgets('shows empty state when no unsold records exist for date',
        (tester) async {
      tester.view.physicalSize = const Size(2560, 1600);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(wrap(const UnsoldHistoryScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Unsold history'), findsOneWidget);
      expect(
          find.text('No unsold products recorded on this day.'), findsOneWidget);
    });

    testWidgets('shows unsold sessions and expands to show product lines',
        (tester) async {
      tester.view.physicalSize = const Size(2560, 1600);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);

      final products = await productRepo.allProducts();
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
          qty: 4,
          businessDate: formatIsoDate(now),
          recordedAt: now,
        ),
        UnsoldLog(
          id: null,
          productId: p2.id,
          productName: p2.name,
          category: p2.category,
          unitPrice: p2.price,
          qty: 3,
          businessDate: formatIsoDate(now),
          recordedAt: now,
        ),
      ]);

      await tester.pumpWidget(wrap(const UnsoldHistoryScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Unsold history'), findsOneWidget);
      expect(find.textContaining('Total: 7 unsold units'), findsOneWidget);
      expect(find.text('Session at ${formatHourMinute(now)}'), findsOneWidget);

      // Tap to expand session.
      await tester.tap(find.text('Session at ${formatHourMinute(now)}'));
      await tester.pumpAndSettle();

      expect(find.text('4×'), findsOneWidget);
      expect(find.text(p1.name), findsOneWidget);
      expect(find.text('3×'), findsOneWidget);
      expect(find.text(p2.name), findsOneWidget);
    });
  });
}
