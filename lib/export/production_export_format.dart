/// Constants describing the production workbook layout.
///
/// Like the expenses workbook, there is no legacy format to match — the
/// downstream script does not read this file. The shape mirrors the expenses
/// workbook column for column where the concepts overlap (date, time, product,
/// status) so that a reader who opens all three files each month sees the same
/// familiar structure.
library;

/// Sheet names in the production workbook.
const String kProductionLinesSheetName = 'Production Lines';
const String kProductionDaySummarySheetName = 'Day Summary';

/// `Production Lines` header, in order.
const List<String> kProductionLinesHeader = [
  'Date',
  'Time',
  'Product Name',
  'Category',
  'Unit Price (RWF)',
  'Qty',
  'Total Value (RWF)',
];

/// Column widths for `Production Lines`, columns A–G.
const List<double> kProductionLinesColumnWidths = [
  12, 8, 30, 16, 16, 7, 17,
];

/// `Day Summary` header, in order.
const List<String> kProductionDaySummaryHeader = [
  'Date',
  'Products Recorded',
  'Total Qty',
  'Total Value (RWF)',
];
