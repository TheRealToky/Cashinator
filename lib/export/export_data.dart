import '../core/app_date.dart';
import '../data/models/order.dart';
import '../repositories/order_repository.dart';
import 'export_format.dart';

// Builds the two sheets as plain data, with no Excel library involved.
//
// Keeping the layout logic pure means the awkward parts — which lines count
// toward a day's totals, how payment columns are ordered, where the `SUM()`
// ranges point — are unit-testable without writing a file.

/// One row of the `Sales Lines` sheet.
class SalesLineRow {
  const SalesLineRow({
    required this.lineId,
    required this.orderId,
    required this.orderLabel,
    required this.productName,
    required this.qty,
    required this.paymentMethod,
    required this.time,
    required this.date,
    required this.sourceImage,
    required this.totalPrice,
    required this.status,
    required this.confidence,
    required this.notes,
  });

  final int lineId;
  final int orderId;
  final String orderLabel;
  final String productName;
  final int qty;
  final String paymentMethod;
  final String time;
  final String date;
  final int sourceImage;
  final int totalPrice;
  final String status;
  final String confidence;
  final String notes;

  /// Cell values in column order, matching [kSalesLinesHeader].
  List<Object?> toCells() => [
        lineId,
        orderId,
        orderLabel,
        productName,
        qty,
        paymentMethod,
        time,
        date,
        sourceImage,
        totalPrice,
        status,
        confidence,
        notes,
      ];
}

/// One row of the `Day Summary` sheet.
class DaySummaryRow {
  const DaySummaryRow({
    required this.sourceImage,
    required this.date,
    required this.orders,
    required this.lines,
    required this.totalSales,
    required this.byPaymentMethod,
  });

  /// Sequential day index within this export batch — the legacy convention.
  final int sourceImage;

  /// Not written to the sheet; used for ordering and for the file name.
  final String date;

  final int orders;
  final int lines;
  final int totalSales;

  /// Keyed by payment method name; every column in the sheet has an entry.
  final Map<String, int> byPaymentMethod;

  List<Object?> toCells(List<String> paymentColumns) => [
        sourceImage,
        orders,
        lines,
        totalSales,
        for (final column in paymentColumns) byPaymentMethod[column] ?? 0,
        kLowConfidenceLines,
      ];
}

/// The complete contents of an export, ready to be written.
class ExportWorkbookData {
  const ExportWorkbookData({
    required this.salesLines,
    required this.daySummaries,
    required this.paymentColumns,
    required this.from,
    required this.to,
  });

  final List<SalesLineRow> salesLines;
  final List<DaySummaryRow> daySummaries;

  /// Payment method columns in sheet order.
  final List<String> paymentColumns;

  final DateTime from;
  final DateTime to;

  bool get isEmpty => salesLines.isEmpty;

  /// Full `Day Summary` header including the dynamic payment columns.
  List<String> get daySummaryHeader => [
        ...kDaySummaryLeadingHeader,
        ...paymentColumns,
        ...kDaySummaryTrailingHeader,
      ];
}

/// Turns orders into the exact rows the legacy format expects.
class ExportDataBuilder {
  const ExportDataBuilder();

  ExportWorkbookData build({
    required List<OrderWithLines> orders,
    required DateTime from,
    required DateTime to,
  }) {
    // Deterministic order: by business date, then by when the sale happened.
    final sorted = [...orders]..sort((a, b) {
        final byDate = a.order.businessDate.compareTo(b.order.businessDate);
        if (byDate != 0) return byDate;
        final byTime = a.order.createdAt.compareTo(b.order.createdAt);
        if (byTime != 0) return byTime;
        return (a.order.id ?? 0).compareTo(b.order.id ?? 0);
      });

    final salesLines = <SalesLineRow>[];
    var lineId = 1;

    for (final entry in sorted) {
      final order = entry.order;
      // Voided orders keep every line in this sheet — that is the audit trail.
      // They are excluded from Day Summary sums further down.
      final notes = order.isVoided ? (order.voidReason ?? '') : '';

      for (final line in entry.lines) {
        salesLines.add(SalesLineRow(
          lineId: lineId++,
          orderId: order.id ?? 0,
          orderLabel: order.orderLabel,
          productName: line.productName,
          qty: line.qty,
          paymentMethod: order.paymentMethodName,
          time: order.timeLabel,
          date: order.businessDate,
          sourceImage: kSourceImageForSalesLines,
          totalPrice: line.lineTotal,
          status: order.status.wireName,
          confidence: kConfidenceValue,
          notes: notes,
        ));
      }
    }

    return ExportWorkbookData(
      salesLines: salesLines,
      daySummaries: _buildDaySummaries(sorted),
      paymentColumns: _resolvePaymentColumns(sorted),
      from: startOfDay(from),
      to: startOfDay(to),
    );
  }

  /// The three legacy columns first, then any other method used in the range.
  ///
  /// Extra methods are sorted so two exports of the same data always produce
  /// the same column order.
  List<String> _resolvePaymentColumns(List<OrderWithLines> orders) {
    final extras = <String>{};

    for (final entry in orders) {
      // Only methods that actually moved money earn a column; a voided-only
      // method would otherwise add a column of zeroes.
      if (entry.order.status != OrderStatus.normal) continue;

      final name = entry.order.paymentMethodName.trim();
      if (name.isEmpty) continue;

      final isBaseline = kBaselinePaymentColumns
          .any((column) => column.toLowerCase() == name.toLowerCase());
      if (!isBaseline) extras.add(name);
    }

    final sortedExtras = extras.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    return [...kBaselinePaymentColumns, ...sortedExtras];
  }

  /// One row per day that has at least one order.
  ///
  /// Days with only voided orders still get a row — their lines appear in
  /// `Sales Lines`, and a summary row of zeroes is what reconciles them.
  List<DaySummaryRow> _buildDaySummaries(List<OrderWithLines> orders) {
    final byDate = <String, List<OrderWithLines>>{};
    for (final entry in orders) {
      byDate
          .putIfAbsent(entry.order.businessDate, () => <OrderWithLines>[])
          .add(entry);
    }

    final dates = byDate.keys.toList()..sort();
    final summaries = <DaySummaryRow>[];

    for (var index = 0; index < dates.length; index++) {
      final date = dates[index];
      final dayOrders = byDate[date]!;

      // Only `normal` rows count. This is the one place the two sheets
      // deliberately disagree: voided lines are visible above, absent here.
      final counted =
          dayOrders.where((e) => e.order.status == OrderStatus.normal).toList();

      var lineCount = 0;
      var totalSales = 0;
      final byMethod = <String, int>{};

      for (final entry in counted) {
        lineCount += entry.lines.length;
        for (final line in entry.lines) {
          totalSales += line.lineTotal;
        }

        final method = _canonicalPaymentName(entry.order.paymentMethodName);
        final orderTotal =
            entry.lines.fold(0, (sum, line) => sum + line.lineTotal);
        byMethod[method] = (byMethod[method] ?? 0) + orderTotal;
      }

      summaries.add(DaySummaryRow(
        // Legacy `Source Image`: sequential index within the batch, 1-based.
        sourceImage: index + 1,
        date: date,
        orders: counted.length,
        lines: lineCount,
        totalSales: totalSales,
        byPaymentMethod: byMethod,
      ));
    }

    return summaries;
  }

  /// Folds case variants onto the baseline spelling so "Momo" lands in the
  /// "MoMo" column instead of creating a second one. The legacy exports contain
  /// exactly that split; the database's NOCASE index prevents it going forward,
  /// but data imported from elsewhere may still carry it.
  String _canonicalPaymentName(String name) {
    final trimmed = name.trim();
    for (final baseline in kBaselinePaymentColumns) {
      if (baseline.toLowerCase() == trimmed.toLowerCase()) return baseline;
    }
    return trimmed;
  }
}
