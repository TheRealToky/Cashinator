import '../../core/app_date.dart';

/// Lifecycle of an order. Voiding is a status change, never a delete — the row
/// stays in the database and keeps appearing in the Excel `Sales Lines` sheet
/// so the day can be audited.
enum OrderStatus {
  normal('normal'),
  voided('voided');

  const OrderStatus(this.wireName);

  /// The exact string written to SQLite and to the `Status` export column.
  final String wireName;

  static OrderStatus fromWire(String? value) => switch (value) {
        'voided' => OrderStatus.voided,
        _ => OrderStatus.normal,
      };
}

/// One sale: a payment method, a timestamp, and one or more [OrderLine]s.
///
/// [paymentMethodName] is snapshotted alongside [paymentMethodId] for the same
/// reason line items snapshot the product name — a method renamed from "MoMo"
/// to "Mobile Money" next month must not silently rewrite last month's export.
class Order {
  const Order({
    required this.id,
    required this.orderLabel,
    required this.businessDate,
    required this.createdAt,
    required this.paymentMethodId,
    required this.paymentMethodName,
    required this.status,
    required this.total,
    this.voidReason,
    this.voidedAt,
  });

  final int? id;

  /// The number staff see and say out loud — a per-day sequence starting at 1.
  /// Distinct from [id], which is globally unique and never reused.
  final String orderLabel;

  /// `YYYY-MM-DD`. Denormalised from [createdAt] so range queries stay a plain
  /// indexed string comparison.
  final String businessDate;

  final DateTime createdAt;
  final int? paymentMethodId;
  final String paymentMethodName;
  final OrderStatus status;

  /// Sum of the line totals, in whole RWF.
  final int total;

  final String? voidReason;
  final DateTime? voidedAt;

  bool get isVoided => status == OrderStatus.voided;

  /// `HH:MM`, for display and for the export `Time` column.
  String get timeLabel => formatHourMinute(createdAt);

  Order copyWith({
    int? id,
    String? orderLabel,
    String? businessDate,
    DateTime? createdAt,
    int? paymentMethodId,
    String? paymentMethodName,
    OrderStatus? status,
    int? total,
    String? voidReason,
    DateTime? voidedAt,
  }) {
    return Order(
      id: id ?? this.id,
      orderLabel: orderLabel ?? this.orderLabel,
      businessDate: businessDate ?? this.businessDate,
      createdAt: createdAt ?? this.createdAt,
      paymentMethodId: paymentMethodId ?? this.paymentMethodId,
      paymentMethodName: paymentMethodName ?? this.paymentMethodName,
      status: status ?? this.status,
      total: total ?? this.total,
      voidReason: voidReason ?? this.voidReason,
      voidedAt: voidedAt ?? this.voidedAt,
    );
  }

  Map<String, Object?> toRow() => {
        if (id != null) 'id': id,
        'order_label': orderLabel,
        'business_date': businessDate,
        'created_at': createdAt.toIso8601String(),
        'payment_method_id': paymentMethodId,
        'payment_method_name': paymentMethodName,
        'status': status.wireName,
        'total': total,
        'void_reason': voidReason,
        'voided_at': voidedAt?.toIso8601String(),
      };

  factory Order.fromRow(Map<String, Object?> row) {
    final voidedAtRaw = row['voided_at'] as String?;
    return Order(
      id: row['id'] as int?,
      orderLabel: row['order_label'] as String? ?? '',
      businessDate: row['business_date'] as String? ?? '',
      createdAt:
          DateTime.tryParse(row['created_at'] as String? ?? '') ?? DateTime.now(),
      paymentMethodId: row['payment_method_id'] as int?,
      paymentMethodName: row['payment_method_name'] as String? ?? '',
      status: OrderStatus.fromWire(row['status'] as String?),
      total: (row['total'] as int?) ?? 0,
      voidReason: row['void_reason'] as String?,
      voidedAt: voidedAtRaw == null ? null : DateTime.tryParse(voidedAtRaw),
    );
  }
}
