import 'package:cashinator/core/app_date.dart';
import 'package:cashinator/data/db/app_database.dart';
import 'package:cashinator/data/models/expense.dart';
import 'package:cashinator/repositories/expense_repository.dart';
import 'package:cashinator/repositories/payment_method_repository.dart';
import 'package:cashinator/ui/backoffice/expenses_screen.dart';
import 'package:cashinator/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Drives the Add expense form the way a manager does, and holds it to the two
/// things that matter: what it records is what was typed, and it cannot be
/// made to write a half-filled row.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    // See pos_flow_test: the isolate factory deadlocks under the fake clock.
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  late AppDatabase database;
  late ExpenseRepository expenses;

  setUp(() async {
    database = await AppDatabase.open(fileName: inMemoryDatabasePath);
    expenses = ExpenseRepository(database);
  });

  tearDown(() async {
    await database.close();
  });

  Widget wrap() => MultiProvider(
        providers: [
          Provider<ExpenseRepository>.value(value: expenses),
          Provider<PaymentMethodRepository>(
            create: (_) => PaymentMethodRepository(database),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const ExpensesScreen(),
        ),
      );

  /// A tablet-sized surface, so the sheet lays out the way it does on the Tab.
  void useTabletSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(2560, 1600);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
  }

  Future<void> openForm(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(FilledButton, 'Add expense'));
    await tester.pumpAndSettle();
  }

  testWidgets('records what was typed, on the method that was tapped', (
    tester,
  ) async {
    useTabletSurface(tester);

    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    expect(find.text('Nothing recorded on this day.'), findsOneWidget);

    await openForm(tester);
    expect(find.text('How was it paid?'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).at(0), 'Milk');
    await tester.enterText(find.byType(TextFormField).at(1), '12000');
    await tester.pumpAndSettle();

    // The read-back shows the amount grouped, so a stray zero is visible.
    expect(find.text('12 000 RWF'), findsOneWidget);

    // Tapping the method confirms, exactly as it does on the till.
    await tester.tap(find.widgetWithText(FilledButton, 'MoMo'));
    await tester.pumpAndSettle();

    final stored = await expenses.expensesForDate(DateTime.now());
    expect(stored, hasLength(1));
    expect(stored.single.name, 'Milk');
    expect(stored.single.amount, 12000);
    expect(stored.single.paymentMethodName, 'MoMo');
    expect(stored.single.status, ExpenseStatus.normal);
    expect(stored.single.businessDate, formatIsoDate(DateTime.now()));

    // ...and the day reads back on screen.
    expect(find.text('12 000 RWF'), findsWidgets);
  });

  testWidgets('will not record a nameless or zero expense', (tester) async {
    useTabletSurface(tester);

    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();
    await openForm(tester);

    // Nothing filled in: the method tap must not close the sheet.
    await tester.tap(find.widgetWithText(FilledButton, 'Cash'));
    await tester.pumpAndSettle();

    expect(find.text('Give the expense a name.'), findsOneWidget);
    expect(find.text('How was it paid?'), findsOneWidget);
    expect(await expenses.expensesForDate(DateTime.now()), isEmpty);

    // A name but a zero amount is still refused.
    await tester.enterText(find.byType(TextFormField).at(0), 'Milk');
    await tester.enterText(find.byType(TextFormField).at(1), '0');
    await tester.tap(find.widgetWithText(FilledButton, 'Cash'));
    await tester.pumpAndSettle();

    expect(find.text('Enter an amount above zero.'), findsOneWidget);
    expect(await expenses.expensesForDate(DateTime.now()), isEmpty);
  });

  testWidgets('voiding keeps the row and drops it from the day total', (
    tester,
  ) async {
    useTabletSurface(tester);

    final methods =
        await PaymentMethodRepository(database).activeMethods();
    await expenses.createExpense(
      name: 'Charcoal',
      amount: 8000,
      paymentMethod: methods.first,
    );

    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    expect(find.text('8 000 RWF'), findsWidgets);

    await tester.tap(find.text('Charcoal'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, 'Void this expense'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).last, 'Paid by the owner');
    await tester.tap(find.widgetWithText(FilledButton, 'Void expense'));
    await tester.pumpAndSettle();

    final stored = await expenses.expensesForDate(DateTime.now());
    expect(stored, hasLength(1));
    expect(stored.single.status, ExpenseStatus.voided);
    expect(stored.single.voidReason, 'Paid by the owner');

    final totals = await expenses.totalsForDate(DateTime.now());
    expect(totals.spend, 0);
    expect(totals.voidedCount, 1);

    // The row is still on screen, struck through and badged.
    expect(find.text('Charcoal'), findsOneWidget);
    expect(find.text('VOIDED'), findsOneWidget);
  });
}
