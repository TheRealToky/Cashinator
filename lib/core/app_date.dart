/// Date and time helpers.
///
/// The Excel export format is strict about shapes: dates are `YYYY-MM-DD` and
/// times are `HH:MM`, both written as text. Storing them as ISO strings in
/// SQLite keeps lexicographic ordering equal to chronological ordering, which
/// is what the history and export range queries rely on.
library;

/// `YYYY-MM-DD` — the business date of an order and the export `Date` column.
String formatIsoDate(DateTime date) {
  final y = date.year.toString().padLeft(4, '0');
  final m = date.month.toString().padLeft(2, '0');
  final d = date.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

/// `HH:MM` — the export `Time` column.
String formatHourMinute(DateTime time) {
  final h = time.hour.toString().padLeft(2, '0');
  final m = time.minute.toString().padLeft(2, '0');
  return '$h:$m';
}

/// Parses a `YYYY-MM-DD` business date back into a [DateTime] at local midnight.
///
/// Returns `null` rather than throwing: these strings come out of the database,
/// and a malformed row should degrade the display, not crash the history list.
DateTime? parseIsoDate(String value) {
  final parts = value.split('-');
  if (parts.length != 3) return null;

  final year = int.tryParse(parts[0]);
  final month = int.tryParse(parts[1]);
  final day = int.tryParse(parts[2]);
  if (year == null || month == null || day == null) return null;
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;

  return DateTime(year, month, day);
}

/// Strips the time component, giving the local-midnight instant for [moment].
DateTime startOfDay(DateTime moment) =>
    DateTime(moment.year, moment.month, moment.day);

/// The first day of the month containing [moment].
DateTime startOfMonth(DateTime moment) => DateTime(moment.year, moment.month);

/// Every date from [from] to [to] inclusive, ascending.
///
/// Used by the exporter to lay out `Day Summary` rows: days with no sales still
/// need consideration, and the caller decides whether to skip them.
List<DateTime> daysBetween(DateTime from, DateTime to) {
  final start = startOfDay(from);
  final end = startOfDay(to);
  if (end.isBefore(start)) return const [];

  final days = <DateTime>[];
  var cursor = start;
  while (!cursor.isAfter(end)) {
    days.add(cursor);
    // Add 25h then re-truncate so DST transitions can't drop or repeat a day.
    cursor = startOfDay(cursor.add(const Duration(hours: 25)));
  }
  return days;
}
