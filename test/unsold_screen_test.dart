import 'package:cashinator/data/db/app_database.dart';
import 'package:cashinator/repositories/product_repository.dart';
import 'package:cashinator/repositories/unsold_repository.dart';
import 'package:cashinator/ui/backoffice/unsold_screen.dart';
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
  late UnsoldRepository unsoldRepo;

  setUp(() async {
    database = await AppDatabase.open(fileName: inMemoryDatabasePath);
    productRepo = ProductRepository(database);
    unsoldRepo = UnsoldRepository(database);
  });

  tearDown(() async {
    await database.close();
  });

  Widget wrap() => MultiProvider(
        providers: [
          Provider<ProductRepository>.value(value: productRepo),
          Provider<UnsoldRepository>.value(value: unsoldRepo),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const UnsoldScreen(),
        ),
      );

  testWidgets('Record unsold screen lists active products and allows counting',
      (tester) async {
    tester.view.physicalSize = const Size(2560, 1600);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    expect(find.text('Record Unsold'), findsOneWidget);
    expect(find.text('Tap + to count unsold products'), findsOneWidget);

    // Tap + on the first product.
    final addButtons = find.byIcon(Icons.add);
    expect(addButtons, findsWidgets);
    await tester.tap(addButtons.first);
    await tester.pumpAndSettle();

    expect(find.text('1 counted'), findsOneWidget);
    expect(find.text('Save unsold session (1 product)'), findsOneWidget);

    // Increment again.
    await tester.tap(addButtons.first);
    await tester.pumpAndSettle();

    expect(find.text('Save unsold session (1 product)'), findsOneWidget);

    // Save session.
    await tester.tap(find.text('Save unsold session (1 product)'));
    await tester.pumpAndSettle();

    final logs = await unsoldRepo.logsForDate(DateTime.now());
    expect(logs, hasLength(1));
    expect(logs.first.qty, 2);

    // Counters should be reset.
    expect(find.text('Tap + to count unsold products'), findsOneWidget);
  });
}
