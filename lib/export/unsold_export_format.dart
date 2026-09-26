/// Constants describing the unsold workbook layout.
///
/// Follows the same format as production and expenses:
/// Two sheets: `Unsold Lines` and `Day Summary`.
library;

/// Sheet names in the unsold workbook.
const String kUnsoldLinesSheetName = 'Unsold Lines';
const String kUnsoldDaySummarySheetName = 'Day Summary';

/// `Unsold Lines` header, in order.
const List<String> kUnsoldLinesHeader = [
  'Date',
  'Time',
  'Product Name',
  'Category',
  'Unit Price (RWF)',
  'Qty',
  'Total Value (RWF)',
];

/// Column widths for `Unsold Lines`, columns A–G.
const List<double> kUnsoldLinesColumnWidths = [
  12, 8, 30, 16, 16, 7, 17,
];

/// `Day Summary` header, in order.
const List<String> kUnsoldDaySummaryHeader = [
  'Date',
  'Products Recorded',
  'Total Qty',
  'Total Value (RWF)',
];
