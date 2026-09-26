import '../../core/app_date.dart';

/// One line of an unsold recording session: how many units of a given product
/// remained unsold at the end of the day.
///
/// Several [UnsoldLog] rows share the same [recordedAt] timestamp when they
/// belong to the same recording session.
///
/// [unitPrice] is snapshotted from the product at recording time.
class UnsoldLog {
  const UnsoldLog({
    required this.id,
    required this.productId,
    required this.productName,
    this.category,
    required this.unitPrice,
    required this.qty,
    required this.businessDate,
    required this.recordedAt,
  });

  final int? id;

  /// Nullable: a product deactivated after recording keeps its name snapshot.
  final int? productId;

  /// Snapshot of the product name at recording time.
  final String productName;

  final String? category;

  /// Whole RWF, snapshotted at recording time.
  final int unitPrice;

  /// Number of unsold units. Always positive — zero-qty lines are filtered
  /// out before being persisted.
  final int qty;

  /// `YYYY-MM-DD`. Denormalised from [recordedAt] so range queries stay fast.
  final String businessDate;

  /// The moment the session was saved. Shared across all lines in one session.
  final DateTime recordedAt;

  /// Derived: whole RWF value of this line.
  int get lineValue => qty * unitPrice;

  /// `HH:MM`, for display.
  String get timeLabel => formatHourMinute(recordedAt);

  UnsoldLog copyWith({
    int? id,
    int? productId,
    String? productName,
    String? category,
    int? unitPrice,
    int? qty,
    String? businessDate,
    DateTime? recordedAt,
    bool clearCategory = false,
  }) {
    return UnsoldLog(
      id: id ?? this.id,
      productId: productId ?? this.productId,
      productName: productName ?? this.productName,
      category: clearCategory ? null : (category ?? this.category),
      unitPrice: unitPrice ?? this.unitPrice,
      qty: qty ?? this.qty,
      businessDate: businessDate ?? this.businessDate,
      recordedAt: recordedAt ?? this.recordedAt,
    );
  }

  Map<String, Object?> toRow() => {
        if (id != null) 'id': id,
        'product_id': productId,
        'product_name': productName.trim(),
        'category': category?.trim(),
        'unit_price': unitPrice,
        'qty': qty,
        'business_date': businessDate,
        'recorded_at': recordedAt.toIso8601String(),
      };

  factory UnsoldLog.fromRow(Map<String, Object?> row) => UnsoldLog(
        id: row['id'] as int?,
        productId: row['product_id'] as int?,
        productName: row['product_name'] as String? ?? '',
        category: row['category'] as String?,
        unitPrice: (row['unit_price'] as int?) ?? 0,
        qty: (row['qty'] as int?) ?? 0,
        businessDate: row['business_date'] as String? ?? '',
        recordedAt: DateTime.tryParse(row['recorded_at'] as String? ?? '') ??
            DateTime.now(),
      );
}

/// Aggregate unsold figures for one business day.
class UnsoldDayTotals {
  const UnsoldDayTotals({
    required this.date,
    required this.itemCount,
    required this.totalQty,
    required this.totalValue,
  });

  final DateTime date;

  /// Number of distinct product lines recorded on this day.
  final int itemCount;

  /// Total units unsold (sum of all qtys).
  final int totalQty;

  /// Whole RWF value of all unsold units (sum of qty × unitPrice).
  final int totalValue;
}
