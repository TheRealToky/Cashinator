/// One product row within an [Order].
///
/// [productName] and [unitPrice] are snapshots taken when the sale was rung up.
/// The exporter reads these columns directly and never joins back to `products`
/// — if a croissant goes from 3 000 to 3 500 RWF next month, June's export must
/// still say 3 000.
class OrderLine {
  const OrderLine({
    required this.id,
    required this.orderId,
    required this.productId,
    required this.productName,
    required this.qty,
    required this.unitPrice,
    this.lineNo = 0,
  });

  final int? id;
  final int? orderId;

  /// Nullable on purpose: the snapshot is authoritative, and a line must remain
  /// readable even if its catalogue row is somehow gone.
  final int? productId;

  final String productName;
  final int qty;
  final int unitPrice;
  final int lineNo;

  /// The `Total Price` export column: quantity times the snapshotted price.
  int get lineTotal => qty * unitPrice;

  OrderLine copyWith({
    int? id,
    int? orderId,
    int? productId,
    String? productName,
    int? qty,
    int? unitPrice,
    int? lineNo,
  }) {
    return OrderLine(
      id: id ?? this.id,
      orderId: orderId ?? this.orderId,
      productId: productId ?? this.productId,
      productName: productName ?? this.productName,
      qty: qty ?? this.qty,
      unitPrice: unitPrice ?? this.unitPrice,
      lineNo: lineNo ?? this.lineNo,
    );
  }

  Map<String, Object?> toRow() => {
        if (id != null) 'id': id,
        'order_id': orderId,
        'product_id': productId,
        'product_name': productName,
        'qty': qty,
        'unit_price': unitPrice,
        'line_total': lineTotal,
        'line_no': lineNo,
      };

  factory OrderLine.fromRow(Map<String, Object?> row) => OrderLine(
        id: row['id'] as int?,
        orderId: row['order_id'] as int?,
        productId: row['product_id'] as int?,
        productName: row['product_name'] as String? ?? '',
        qty: (row['qty'] as int?) ?? 0,
        unitPrice: (row['unit_price'] as int?) ?? 0,
        lineNo: (row['line_no'] as int?) ?? 0,
      );
}
