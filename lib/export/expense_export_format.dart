/// Constants describing the expenses workbook layout.
///
/// Unlike `export_format.dart`, nothing here is dictated by the legacy OCR
/// ledgers — there were never any expense sheets to match, and the downstream
/// sales script does not read this file. The layout still mirrors the sales
/// workbook column for column where the two have the same idea (payment
/// method, time, date, status, notes) so that whoever reads both files each
/// month is reading the same shape twice, and the OCR-era relics
/// (`Source Image`, `Confidence`, `Low Confidence Lines`) are left out because
/// they never meant anything here.
library;

/// Sheet names in the expenses workbook.
const String kExpensesSheetName = 'Expenses';
const String kExpenseDaySummarySheetName = 'Day Summary';

/// `Expenses` header, in order.
const List<String> kExpensesHeader = [
  'Expense Id',
  'Name',
  'Amount (RWF)',
  'Payment Method',
  'Time',
  'Date',
  'Status',
  'Notes',
];

/// Column widths for `Expenses`, columns A–H.
const List<double> kExpensesColumnWidths = [
  11, 30, 14, 16, 8, 12, 10, 40,
];

/// Fixed part of the expenses `Day Summary` header, before the payment
/// columns.
///
/// The sales summary opens with the legacy `Source Image` day index instead of
/// a date; this sheet has no such obligation, so it names the day outright.
const List<String> kExpenseDaySummaryLeadingHeader = [
  'Date',
  'Expenses',
  'Total Spend (RWF)',
];
