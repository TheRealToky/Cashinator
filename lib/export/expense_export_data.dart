import '../core/app_date.dart';
import '../data/models/expense.dart';
import 'export_format.dart';
import 'expense_export_format.dart';

// Builds the expenses workbook as plain data, with no Excel library involved —
// the same split the sales export uses, so which rows count toward a day's
// spend and where the `SUM()` ranges point stay unit-testable without writing
// a file.

/// One row of the `Expenses` sheet.
class ExpenseRow {
  const ExpenseRow({
    required this.expenseId,
    required this.name,
    required this.amount,
    required this.paymentMethod,
    required this.time,
    required this.date,
    required this.status,
    required this.notes,
  });

  final int expenseId;
  final String name;
  final int amount;
  final String paymentMethod;
  final String time;
  final String date;
  final String status;
  final String notes;

  /// Cell values in column order, matching [kExpensesHeader].
  List<Object?> toCells() => [
        expenseId,
        name,
        amount,
        paymentMethod,
        time,
        date,
        status,
        notes,
      ];
}

/// One row of the expenses `Day Summary` sheet.
class ExpenseDaySummaryRow {
  const ExpenseDaySummaryRow({
    required this.date,
    required this.expenses,
    required this.totalSpend,
    required this.byPaymentMethod,
  });

  /// `YYYY-MM-DD`, written to the sheet as text.
  final String date;

  final int expenses;
  final int totalSpend;

  /// Keyed by payment method name; every column in the sheet has an entry.
  final Map<String, int> byPaymentMethod;

  List<Object?> toCells(List<String> paymentColumns) => [
        date,
        expenses,
        totalSpend,
        for (final column in paymentColumns) byPaymentMethod[column] ?? 0,
      ];
}

/// The complete contents of an expenses export, ready to be written.
class ExpenseWorkbookData {
  const ExpenseWorkbookData({
    required this.expenses,
    required this.daySummaries,
    required this.paymentColumns,
    required this.from,
    required this.to,
  });

  final List<ExpenseRow> expenses;
  final List<ExpenseDaySummaryRow> daySummaries;

  /// Payment method columns in sheet order.
  final List<String> paymentColumns;

  final DateTime from;
  final DateTime to;

  bool get isEmpty => expenses.isEmpty;

  /// Full `Day Summary` header including the dynamic payment columns.
  List<String> get daySummaryHeader => [
        ...kExpenseDaySummaryLeadingHeader,
        ...paymentColumns,
      ];
}

/// Turns recorded expenses into the rows the workbook expects.
class ExpenseExportBuilder {
  const ExpenseExportBuilder();

  ExpenseWorkbookData build({
    required List<Expense> expenses,
    required DateTime from,
    required DateTime to,
  }) {
    // Deterministic order: by business date, then by when the money went out.
    final sorted = [...expenses]..sort((a, b) {
        final byDate = a.businessDate.compareTo(b.businessDate);
        if (byDate != 0) return byDate;
        final byTime = a.createdAt.compareTo(b.createdAt);
        if (byTime != 0) return byTime;
        return (a.id ?? 0).compareTo(b.id ?? 0);
      });

    final rows = [
      for (final expense in sorted)
        ExpenseRow(
          expenseId: expense.id ?? 0,
          name: expense.name,
          amount: expense.amount,
          paymentMethod: expense.paymentMethodName,
          time: expense.timeLabel,
          date: expense.businessDate,
          status: expense.status.wireName,
          // Voided rows keep their place in this sheet — that is the audit
          // trail — and carry their reason across, exactly as a voided sale
          // does. They are left out of the day totals below.
          notes: expense.isVoided ? (expense.voidReason ?? '') : '',
        ),
    ];

    return ExpenseWorkbookData(
      expenses: rows,
      daySummaries: _buildDaySummaries(sorted),
      paymentColumns: _resolvePaymentColumns(sorted),
      from: startOfDay(from),
      to: startOfDay(to),
    );
  }

  /// The three baseline columns first, then any other method money actually
  /// left by, sorted so two exports of the same data agree.
  List<String> _resolvePaymentColumns(List<Expense> expenses) {
    final extras = <String>{};

    for (final expense in expenses) {
      if (expense.status != ExpenseStatus.normal) continue;

      final name = expense.paymentMethodName.trim();
      if (name.isEmpty) continue;

      final isBaseline = kBaselinePaymentColumns
          .any((column) => column.toLowerCase() == name.toLowerCase());
      if (!isBaseline) extras.add(name);
    }

    final sortedExtras = extras.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    return [...kBaselinePaymentColumns, ...sortedExtras];
  }

  /// One row per day that has at least one expense.
  ///
  /// A day whose expenses were all voided still gets a row of zeroes: the rows
  /// are visible in the `Expenses` sheet, and the zeroes are what reconciles
  /// them.
  List<ExpenseDaySummaryRow> _buildDaySummaries(List<Expense> expenses) {
    final byDate = <String, List<Expense>>{};
    for (final expense in expenses) {
      byDate.putIfAbsent(expense.businessDate, () => <Expense>[]).add(expense);
    }

    final dates = byDate.keys.toList()..sort();
    final summaries = <ExpenseDaySummaryRow>[];

    for (final date in dates) {
      final counted = byDate[date]!
          .where((expense) => expense.status == ExpenseStatus.normal)
          .toList();

      var totalSpend = 0;
      final byMethod = <String, int>{};

      for (final expense in counted) {
        totalSpend += expense.amount;
        final method = _canonicalPaymentName(expense.paymentMethodName);
        byMethod[method] = (byMethod[method] ?? 0) + expense.amount;
      }

      summaries.add(ExpenseDaySummaryRow(
        date: date,
        expenses: counted.length,
        totalSpend: totalSpend,
        byPaymentMethod: byMethod,
      ));
    }

    return summaries;
  }

  /// Folds case variants onto the baseline spelling, so "Momo" lands in the
  /// "MoMo" column instead of opening a second one.
  String _canonicalPaymentName(String name) {
    final trimmed = name.trim();
    for (final baseline in kBaselinePaymentColumns) {
      if (baseline.toLowerCase() == trimmed.toLowerCase()) return baseline;
    }
    return trimmed;
  }
}
