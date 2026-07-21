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
}
