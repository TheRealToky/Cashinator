import '../core/app_date.dart';
import '../data/models/production_log.dart';
import 'production_export_format.dart';

// Builds the production workbook as plain data, with no Excel library involved —
// the same split the sales and expenses exports use, keeping the layout logic
// unit-testable without writing a file.

/// One row of the `Production Lines` sheet.
class ProductionLineRow {
  const ProductionLineRow({
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

  /// Cell values in column order, matching [kProductionLinesHeader].
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

/// One row of the production `Day Summary` sheet.
class ProductionDaySummaryRow {
  const ProductionDaySummaryRow({
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

  /// Cell values in column order, matching [kProductionDaySummaryHeader].
  List<Object?> toCells() => [
        date,
        productsRecorded,
        totalQty,
        totalValue,
      ];
}

/// The complete contents of a production export, ready to be written.
class ProductionWorkbookData {
  const ProductionWorkbookData({
    required this.lines,
    required this.daySummaries,
    required this.from,
    required this.to,
  });

  final List<ProductionLineRow> lines;
  final List<ProductionDaySummaryRow> daySummaries;

  final DateTime from;
  final DateTime to;

  bool get isEmpty => lines.isEmpty;
}

/// Turns [ProductionLog] rows into the workbook data the exporter writes.
class ProductionExportBuilder {
  const ProductionExportBuilder();

  ProductionWorkbookData build({
    required List<ProductionLog> logs,
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
        ProductionLineRow(
          date: log.businessDate,
          time: log.timeLabel,
          productName: log.productName,
          category: log.category,
          unitPrice: log.unitPrice,
          qty: log.qty,
          totalValue: log.lineValue,
        ),
    ];

    return ProductionWorkbookData(
      lines: lines,
      daySummaries: _buildDaySummaries(sorted),
      from: startOfDay(from),
      to: startOfDay(to),
    );
  }

  /// One row per day that has at least one production log.
  List<ProductionDaySummaryRow> _buildDaySummaries(List<ProductionLog> logs) {
    final byDate = <String, List<ProductionLog>>{};
    for (final log in logs) {
      byDate.putIfAbsent(log.businessDate, () => <ProductionLog>[]).add(log);
    }

    final dates = byDate.keys.toList()..sort();
    final summaries = <ProductionDaySummaryRow>[];

    for (final date in dates) {
      final dayLogs = byDate[date]!;
      var totalQty = 0;
      var totalValue = 0;

      for (final log in dayLogs) {
        totalQty += log.qty;
        totalValue += log.lineValue;
      }

      summaries.add(ProductionDaySummaryRow(
        date: date,
        productsRecorded: dayLogs.length,
        totalQty: totalQty,
        totalValue: totalValue,
      ));
    }

    return summaries;
  }
}
