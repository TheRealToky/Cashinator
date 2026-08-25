import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:cashinator/core/app_date.dart';
import 'package:cashinator/data/models/expense.dart';
import 'package:cashinator/export/excel_exporter.dart';
import 'package:cashinator/export/expense_export_data.dart';
import 'package:cashinator/export/expense_export_format.dart';
import 'package:flutter_test/flutter_test.dart';

/// Covers the expenses workbook the same way `export_data_test` covers the
/// sales one: the layout decisions in pure Dart, then a real `.xlsx` on disk.
void main() {
  const builder = ExpenseExportBuilder();
  const exporter = ExcelExporter();

  Expense makeExpense({
    required int id,
    required String name,
    required int amount,
    required String date,
    required String paymentMethod,
    int hour = 9,
    int minute = 0,
    ExpenseStatus status = ExpenseStatus.normal,
    String? voidReason,
  }) {
    final day = parseIsoDate(date)!;
    return Expense(
      id: id,
      name: name,
      amount: amount,
      businessDate: date,
      createdAt: combineDateAndTime(day, hour, minute),
      paymentMethodId: 1,
      paymentMethodName: paymentMethod,
      status: status,
      voidReason: voidReason,
      voidedAt: status == ExpenseStatus.voided ? day : null,
    );
  }

  List<Expense> sampleExpenses() => [
        makeExpense(
          id: 1,
          name: 'Milk',
          amount: 12000,
          date: '2026-08-20',
          paymentMethod: 'Cash',
          hour: 7,
          minute: 40,
        ),
        makeExpense(
          id: 2,
          name: 'Flour',
          amount: 85000,
          date: '2026-08-20',
          paymentMethod: 'MoMo',
          hour: 10,
          minute: 5,
        ),
        makeExpense(
          id: 3,
          name: 'Double-entered flour',
          amount: 85000,
          date: '2026-08-20',
          paymentMethod: 'MoMo',
          hour: 10,
          minute: 6,
          status: ExpenseStatus.voided,
          voidReason: 'Entered twice',
        ),
        makeExpense(
          id: 4,
          name: 'Transport',
          amount: 3000,
          date: '2026-08-21',
          paymentMethod: 'Kivuwatt',
          hour: 8,
          minute: 30,
        ),
      ];

  ExpenseWorkbookData sampleData() => builder.build(
        expenses: sampleExpenses(),
        from: parseIsoDate('2026-08-20')!,
        to: parseIsoDate('2026-08-21')!,
      );

  group('ExpenseExportBuilder', () {
    test('writes one row per expense, oldest first', () {
      final data = sampleData();

      expect(data.expenses.map((row) => row.name), [
        'Milk',
        'Flour',
        'Double-entered flour',
        'Transport',
      ]);
      expect(data.expenses.first.time, '07:40');
      expect(data.expenses.first.date, '2026-08-20');
    });

    test('keeps a voided expense visible and carries its reason to Notes', () {
      final voided =
          sampleData().expenses.firstWhere((row) => row.expenseId == 3);

      expect(voided.status, 'voided');
      expect(voided.notes, 'Entered twice');
      expect(voided.amount, 85000);
    });

    test('leaves voided expenses out of the day totals', () {
      final data = sampleData();
      final firstDay =
          data.daySummaries.firstWhere((row) => row.date == '2026-08-20');

      // 12 000 + 85 000, with the 85 000 duplicate voided away.
      expect(firstDay.totalSpend, 97000);
      expect(firstDay.expenses, 2);
      expect(firstDay.byPaymentMethod['Cash'], 12000);
      expect(firstDay.byPaymentMethod['MoMo'], 85000);
    });

    test('emits the baseline payment columns plus any extra method used', () {
      final data = sampleData();

      expect(data.paymentColumns, ['MoMo', 'Card', 'Cash', 'Kivuwatt']);
      expect(data.daySummaryHeader, [
        ...kExpenseDaySummaryLeadingHeader,
        'MoMo',
        'Card',
        'Cash',
        'Kivuwatt',
      ]);
    });

    test('folds a case variant onto the baseline column', () {
      final data = builder.build(
        expenses: [
          makeExpense(
            id: 1,
            name: 'Airtime',
            amount: 2000,
            date: '2026-08-20',
            paymentMethod: 'momo',
          ),
        ],
        from: parseIsoDate('2026-08-20')!,
        to: parseIsoDate('2026-08-20')!,
      );

      expect(data.paymentColumns, ['MoMo', 'Card', 'Cash']);
      expect(data.daySummaries.single.byPaymentMethod['MoMo'], 2000);
    });

    test('a day whose expenses were all voided still gets a zero row', () {
      final data = builder.build(
        expenses: [
          makeExpense(
            id: 1,
            name: 'Mistake',
            amount: 5000,
            date: '2026-08-20',
            paymentMethod: 'Cash',
            status: ExpenseStatus.voided,
            voidReason: 'Never happened',
          ),
        ],
        from: parseIsoDate('2026-08-20')!,
        to: parseIsoDate('2026-08-20')!,
      );

      expect(data.expenses, hasLength(1));
      expect(data.daySummaries.single.totalSpend, 0);
      expect(data.daySummaries.single.expenses, 0);
    });

    test('an empty range builds an empty workbook rather than throwing', () {
      final day = parseIsoDate('2026-08-20')!;
      final data = builder.build(expenses: const [], from: day, to: day);

      expect(data.isEmpty, isTrue);
      expect(data.daySummaries, isEmpty);
      expect(exporter.buildExpenseWorkbookBytes(data), isNotEmpty);
    });
  });

  group('ExcelExporter', () {
    test('produces a non-trivial xlsx file', () {
      final bytes = exporter.buildExpenseWorkbookBytes(sampleData());

      expect(bytes, isNotEmpty);
      // xlsx is a zip: "PK\x03\x04".
      expect(bytes.take(4).toList(), [0x50, 0x4B, 0x03, 0x04]);
    });

    test('writes both sheets and a conformant TOTAL row', () {
      final bytes = exporter.buildExpenseWorkbookBytes(sampleData());
      final archive = ZipDecoder().decodeBytes(bytes);

      final workbookXml = utf8.decode(
        archive.files
            .firstWhere((file) => file.name == 'xl/workbook.xml')
            .content as List<int>,
      );
      expect(workbookXml, contains(kExpensesSheetName));
      expect(workbookXml, contains(kExpenseDaySummarySheetName));

      // The same regression guard the sales workbook carries: xlsio bakes a
      // leading '=' into <f>, which openpyxl reads doubled.
      var formulaCount = 0;
      for (final file in archive.files) {
        if (!file.name.startsWith('xl/worksheets/') ||
            !file.name.endsWith('.xml')) {
          continue;
        }
        final xml = utf8.decode(file.content as List<int>);
        for (final match in RegExp(r'<f[^>]*>(.*?)</f>').allMatches(xml)) {
          formulaCount++;
          expect(match.group(1)!, startsWith('SUM('));
        }
      }
      expect(formulaCount, greaterThan(0));
    });

    test('writes the workbook to disk for inspection', () async {
      final data = sampleData();
      final bytes = exporter.buildExpenseWorkbookBytes(data);

      final outputDir = Directory('build/test_exports');
      await outputDir.create(recursive: true);
      final file = File('${outputDir.path}/sample_expenses.xlsx');
      await file.writeAsBytes(bytes, flush: true);

      expect(await file.length(), greaterThan(2000));
    });
  });
}
