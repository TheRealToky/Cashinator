import '../../core/app_exception.dart';

/// How an order was paid for.
///
/// Seeded with Cash, MoMo and Card to match what the shop already writes on the
/// paper ledger. Back office can add more — the Excel exporter generates a
/// summary column per method it encounters, so new methods stay visible
/// downstream rather than vanishing into the total.
class PaymentMethod {
  const PaymentMethod({
    required this.id,
    required this.name,
    required this.active,
    this.sortOrder = 0,
  });

  final int? id;
  final String name;
  final bool active;
  final int sortOrder;

  void validate() {
    if (name.trim().isEmpty) {
      throw const ValidationException('Payment method name cannot be empty.');
    }
    if (name.trim().length > 40) {
      throw const ValidationException(
        'Payment method name is too long (40 characters maximum).',
      );
    }
  }

  PaymentMethod copyWith({
    int? id,
    String? name,
    bool? active,
    int? sortOrder,
  }) {
    return PaymentMethod(
      id: id ?? this.id,
      name: name ?? this.name,
      active: active ?? this.active,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }

  Map<String, Object?> toRow() => {
        if (id != null) 'id': id,
        'name': name.trim(),
        'active': active ? 1 : 0,
        'sort_order': sortOrder,
      };

  factory PaymentMethod.fromRow(Map<String, Object?> row) => PaymentMethod(
        id: row['id'] as int?,
        name: row['name'] as String? ?? '',
        active: (row['active'] as int? ?? 1) == 1,
        sortOrder: (row['sort_order'] as int?) ?? 0,
      );
}
