import 'package:cashinator/core/app_date.dart';
import 'package:cashinator/core/money.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatRwf', () {
    test('groups thousands', () {
      expect(formatRwf(0), '0');
      expect(formatRwf(500), '500');
      expect(formatRwf(7500), '7 500');
      expect(formatRwf(116200), '116 200');
      expect(formatRwf(1234567), '1 234 567');
    });

    test('handles negatives', () {
      expect(formatRwf(-2000), '-2 000');
    });

    test('appends the unit', () {
      expect(formatRwfWithUnit(3000), '3 000 RWF');
    });
  });

  group('date formatting', () {
    test('formats the export shapes', () {
      final moment = DateTime(2026, 6, 19, 7, 31);
      expect(formatIsoDate(moment), '2026-06-19');
      expect(formatHourMinute(moment), '07:31');
    });

    test('pads single digits', () {
      expect(formatIsoDate(DateTime(2026, 1, 2)), '2026-01-02');
      expect(formatHourMinute(DateTime(2026, 1, 2, 5, 4)), '05:04');
    });

    test('round-trips a business date', () {
      expect(parseIsoDate('2026-06-19'), DateTime(2026, 6, 19));
    });

    test('moves the clock on a day without moving the date', () {
      final day = DateTime(2026, 6, 19, 16, 44, 30);
      final corrected = combineDateAndTime(day, 9, 5);

      expect(formatIsoDate(corrected), formatIsoDate(day));
      expect(formatHourMinute(corrected), '09:05');
      // Seconds are dropped: the export carries HH:MM, so keeping them would
      // only make two sales at "09:05" sort by something invisible.
      expect(corrected.second, 0);
    });

    test('returns null on malformed input rather than throwing', () {
      expect(parseIsoDate('not-a-date'), isNull);
      expect(parseIsoDate('2026-13-01'), isNull);
      expect(parseIsoDate('2026-06'), isNull);
    });
  });

  group('daysBetween', () {
    test('is inclusive at both ends', () {
      final days = daysBetween(DateTime(2026, 7, 20), DateTime(2026, 7, 23));
      expect(days.map(formatIsoDate), [
        '2026-07-20',
        '2026-07-21',
        '2026-07-22',
        '2026-07-23',
      ]);
    });

    test('handles a single day', () {
      final days = daysBetween(DateTime(2026, 7, 20), DateTime(2026, 7, 20));
      expect(days, hasLength(1));
    });

    test('returns empty for an inverted range', () {
      expect(daysBetween(DateTime(2026, 7, 20), DateTime(2026, 7, 10)), isEmpty);
    });

    test('crosses a month boundary', () {
      final days = daysBetween(DateTime(2026, 6, 29), DateTime(2026, 7, 2));
      expect(days.map(formatIsoDate), [
        '2026-06-29',
        '2026-06-30',
        '2026-07-01',
        '2026-07-02',
      ]);
    });
  });

  test('startOfMonth drops the day and time', () {
    expect(startOfMonth(DateTime(2026, 7, 20, 14, 5)), DateTime(2026, 7, 1));
  });

  group('daysApart', () {
    test('counts calendar days, not elapsed hours', () {
      // Late on one evening to early the next morning is nine hours, but it is
      // still one day apart — which is what "Yesterday" has to key off.
      expect(
        daysApart(DateTime(2026, 8, 12, 23, 30), DateTime(2026, 8, 13, 8, 15)),
        1,
      );
    });

    test('is signed and zero within a day', () {
      expect(daysApart(DateTime(2026, 8, 13), DateTime(2026, 8, 12)), -1);
      expect(daysApart(DateTime(2026, 8, 13, 6), DateTime(2026, 8, 13, 22)), 0);
      expect(daysApart(DateTime(2026, 7, 30), DateTime(2026, 8, 13)), 14);
    });
  });

  group('isSameDate', () {
    test('ignores the clock', () {
      expect(
        isSameDate(DateTime(2026, 8, 13, 0, 1), DateTime(2026, 8, 13, 23, 59)),
        isTrue,
      );
      expect(isSameDate(DateTime(2026, 8, 13), DateTime(2026, 8, 12)), isFalse);
      // Same day number, different month — the cheap comparison must not pass.
      expect(isSameDate(DateTime(2026, 8, 13), DateTime(2026, 7, 13)), isFalse);
    });
  });

  group('sale date labels', () {
    // A Thursday.
    final today = DateTime(2026, 8, 13);

    test('names the two days staff actually backdate to', () {
      expect(formatRelativeDate(today, today: today), 'Today');
      expect(
        formatRelativeDate(DateTime(2026, 8, 12), today: today),
        'Yesterday',
      );
    });

    test('falls back to a weekday and date further out', () {
      expect(formatRelativeDate(DateTime(2026, 8, 9), today: today), 'Sun 9 Aug');
      expect(
        formatRelativeDate(DateTime(2026, 7, 30), today: today),
        'Thu 30 Jul',
      );
    });

    test('is unaffected by the time of day on either side', () {
      expect(
        formatRelativeDate(DateTime(2026, 8, 12, 19, 40),
            today: DateTime(2026, 8, 13, 6, 5)),
        'Yesterday',
      );
    });

    test('formatShortDate leads with the weekday', () {
      expect(formatShortDate(DateTime(2026, 1, 2)), 'Fri 2 Jan');
      expect(formatShortDate(DateTime(2026, 12, 31)), 'Thu 31 Dec');
    });
  });
}
