import '../core/app_date.dart';
import '../data/models/unsold_log.dart';
import 'unsold_export_format.dart';

/// One row of the `Unsold Lines` sheet.
class UnsoldLineRow {
  const UnsoldLineRow({
    required this.date,
    required this.time,
    required this.productName,
    required this.category,
    required this.unitPrice,
    required this.qty,
    required this.totalValue,
  });

  final String date;
  final String time;
  final String productName;
  final String? category;
  final int unitPrice;
  final int qty;
  final int totalValue;

  /// Cell values in column order, matching [kUnsoldLinesHeader].
  List<Object?> toCells() => [
        date,
        time,
        productName,
        category ?? '',
        unitPrice,
        qty,
        totalValue,
      ];
}

/// One row of the unsold `Day Summary` sheet.
class UnsoldDaySummaryRow {
  const UnsoldDaySummaryRow({
    required this.date,
    required this.productsRecorded,
    required this.totalQty,
    required this.totalValue,
  });

  /// `YYYY-MM-DD`, written to the sheet as text.
  final String date;

  /// Number of distinct product lines on this day.
  final int productsRecorded;

  /// Sum of all qty values on this day.
  final int totalQty;

  /// Sum of qty × unitPrice on this day, in whole RWF.
  final int totalValue;

  /// Cell values in column order, matching [kUnsoldDaySummaryHeader].
  List<Object?> toCells() => [
        date,
        productsRecorded,
        totalQty,
        totalValue,
      ];
}

/// The complete contents of an unsold export, ready to be written.
class UnsoldWorkbookData {
  const UnsoldWorkbookData({
    required this.lines,
    required this.daySummaries,
    required this.from,
    required this.to,
  });

  final List<UnsoldLineRow> lines;
  final List<UnsoldDaySummaryRow> daySummaries;

  final DateTime from;
  final DateTime to;

  bool get isEmpty => lines.isEmpty;
}

/// Turns [UnsoldLog] rows into the workbook data the exporter writes.
class UnsoldExportBuilder {
  const UnsoldExportBuilder();

  UnsoldWorkbookData build({
    required List<UnsoldLog> logs,
    required DateTime from,
    required DateTime to,
  }) {
    // Deterministic order: by business date, then by session time, then by id.
    final sorted = [...logs]..sort((a, b) {
        final byDate = a.businessDate.compareTo(b.businessDate);
        if (byDate != 0) return byDate;
        final byTime = a.recordedAt.compareTo(b.recordedAt);
        if (byTime != 0) return byTime;
        return (a.id ?? 0).compareTo(b.id ?? 0);
      });

    final lines = [
      for (final log in sorted)
        UnsoldLineRow(
          date: log.businessDate,
          time: log.timeLabel,
          productName: log.productName,
          category: log.category,
          unitPrice: log.unitPrice,
          qty: log.qty,
          totalValue: log.lineValue,
        ),
    ];

    return UnsoldWorkbookData(
      lines: lines,
      daySummaries: _buildDaySummaries(sorted),
      from: startOfDay(from),
      to: startOfDay(to),
    );
  }

  /// One row per day that has at least one unsold log.
  List<UnsoldDaySummaryRow> _buildDaySummaries(List<UnsoldLog> logs) {
    final byDate = <String, List<UnsoldLog>>{};
    for (final log in logs) {
      byDate.putIfAbsent(log.businessDate, () => <UnsoldLog>[]).add(log);
    }

    final dates = byDate.keys.toList()..sort();
    final summaries = <UnsoldDaySummaryRow>[];

    for (final date in dates) {
      final dayLogs = byDate[date]!;
      var totalQty = 0;
      var totalValue = 0;

      for (final log in dayLogs) {
        totalQty += log.qty;
        totalValue += log.lineValue;
      }

      summaries.add(UnsoldDaySummaryRow(
        date: date,
        productsRecorded: dayLogs.length,
        totalQty: totalQty,
        totalValue: totalValue,
      ));
    }

    return summaries;
  }
}
