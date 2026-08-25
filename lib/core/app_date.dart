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

/// [day]'s calendar date at [hour]:[minute], local time.
///
/// The two halves of a sale's stamp are chosen separately — the date on the
/// payment sheet, the clock on the time pad — and this is where they meet. The
/// date always comes from [day], so editing the clock can never drag a sale
/// onto a neighbouring day's order sequence or day total by itself. Values
/// outside 0–23 / 0–59 roll over the way [DateTime] does, so callers are
/// expected to have validated them.
DateTime combineDateAndTime(DateTime day, int hour, int minute) =>
    DateTime(day.year, day.month, day.day, hour, minute);

/// Strips the time component, giving the local-midnight instant for [moment].
DateTime startOfDay(DateTime moment) =>
    DateTime(moment.year, moment.month, moment.day);

/// Whole calendar days from [from] to [to]; negative when [to] is earlier.
///
/// Counted in hours and rounded rather than read off `Duration.inDays`, because
/// a DST shift makes two local midnights 23 or 25 hours apart and would
/// otherwise round "yesterday" down to zero days.
int daysApart(DateTime from, DateTime to) =>
    (startOfDay(to).difference(startOfDay(from)).inHours / 24).round();

/// True when [a] and [b] fall on the same calendar day.
bool isSameDate(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Short weekday names, indexed by `DateTime.weekday - 1` (Monday is 1).
///
/// Hardcoded rather than taken from `intl`: the app ships no localisation and
/// every other string in it is English, so a date-formatting package would add
/// a dependency and a locale-init step to produce the same three letters.
const List<String> _shortWeekdays = [
  'Mon',
  'Tue',
  'Wed',
  'Thu',
  'Fri',
  'Sat',
  'Sun',
];

/// Short month names, indexed by `DateTime.month - 1`.
const List<String> _shortMonths = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// `Sat 9 Aug` — a date a cashier can read without decoding it.
///
/// The weekday leads because that is how staff remember which day a missed
/// sale happened on: "the Saturday we were closed", not "the ninth".
String formatShortDate(DateTime date) =>
    '${_shortWeekdays[date.weekday - 1]} ${date.day} '
    '${_shortMonths[date.month - 1]}';

/// [date] named relative to [today]: `Today`, `Yesterday`, else
/// [formatShortDate].
///
/// [today] is passed in rather than read from the clock so the label a screen
/// shows can be pinned for the life of that screen, and so tests do not have to
/// run at a particular moment.
String formatRelativeDate(DateTime date, {required DateTime today}) =>
    switch (daysApart(today, date)) {
      0 => 'Today',
      -1 => 'Yesterday',
      _ => formatShortDate(date),
    };

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
