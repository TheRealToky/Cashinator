import '../../core/app_date.dart';
import '../../core/app_exception.dart';

/// Lifecycle of an expense. Mirrors `OrderStatus`: voiding is a status change,
/// never a delete, so a mistyped expense stays visible in the `Expenses` sheet
/// and can be reconciled against whatever paper it came from.
enum ExpenseStatus {
  normal('normal'),
  voided('voided');

  const ExpenseStatus(this.wireName);

  /// The exact string written to SQLite and to the `Status` export column.
  final String wireName;

  static ExpenseStatus fromWire(String? value) => switch (value) {
        'voided' => ExpenseStatus.voided,
        _ => ExpenseStatus.normal,
      };
}

/// One thing the shop paid for: what it was, what it cost, when, and out of
/// which pocket.
///
/// The shape deliberately echoes `Order` — same stamp columns, same payment
/// method snapshot, same voiding rules — because the two are recorded by the
/// same people on the same tablet and end up side by side in the books. Money
/// is whole RWF, like everywhere else in the app.
///
/// [paymentMethodName] is snapshotted alongside [paymentMethodId] for the same
/// reason an order snapshots it: renaming "MoMo" next month must not rewrite
/// what this expense recorded.
class Expense {
  const Expense({
    required this.id,
    required this.name,
    required this.amount,
    required this.businessDate,
    required this.createdAt,
    required this.paymentMethodId,
    required this.paymentMethodName,
    required this.status,
    this.voidReason,
    this.voidedAt,
  });

  /// A sanity bound on [amount], not a policy: it catches a stray digit on a
  /// tablet keypad while leaving room for rent or an equipment purchase. The
  /// form checks it too, so the figure is questioned while it is still on
  /// screen rather than after the sheet has closed.
  static const int maxAmount = 100000000;

  final int? id;

  /// What the money went on, in the manager's own words — "Milk", "Gas
  /// bottle", "Boda to the market".
  final String name;

  /// Whole RWF, always positive. The sign lives in the fact that this is an
  /// expense, not in the number.
  final int amount;

  /// `YYYY-MM-DD`. Denormalised from [createdAt] so range queries stay a plain
  /// indexed string comparison, exactly as orders do it.
  final String businessDate;

  final DateTime createdAt;
  final int? paymentMethodId;
  final String paymentMethodName;
  final ExpenseStatus status;

  final String? voidReason;
  final DateTime? voidedAt;

  bool get isVoided => status == ExpenseStatus.voided;

  /// `HH:MM`, for display and for the export `Time` column.
  String get timeLabel => formatHourMinute(createdAt);

  /// Validates what the form collected before it reaches the database.
  void validate() {
    if (name.trim().isEmpty) {
      throw const ValidationException('Give the expense a name.');
    }
    if (name.trim().length > 80) {
      throw const ValidationException(
        'Expense name is too long (80 characters maximum).',
      );
    }
    if (amount <= 0) {
      throw const ValidationException('Enter an amount above zero.');
    }
    if (amount > maxAmount) {
      throw const ValidationException('Amount looks wrong — check the figure.');
    }
  }

  Expense copyWith({
    int? id,
    String? name,
    int? amount,
    String? businessDate,
    DateTime? createdAt,
    int? paymentMethodId,
    String? paymentMethodName,
    ExpenseStatus? status,
    String? voidReason,
    DateTime? voidedAt,
  }) {
    return Expense(
      id: id ?? this.id,
      name: name ?? this.name,
      amount: amount ?? this.amount,
      businessDate: businessDate ?? this.businessDate,
      createdAt: createdAt ?? this.createdAt,
      paymentMethodId: paymentMethodId ?? this.paymentMethodId,
      paymentMethodName: paymentMethodName ?? this.paymentMethodName,
      status: status ?? this.status,
      voidReason: voidReason ?? this.voidReason,
      voidedAt: voidedAt ?? this.voidedAt,
    );
  }

  Map<String, Object?> toRow() => {
        if (id != null) 'id': id,
        'name': name.trim(),
        'amount': amount,
        'business_date': businessDate,
        'created_at': createdAt.toIso8601String(),
        'payment_method_id': paymentMethodId,
        'payment_method_name': paymentMethodName,
        'status': status.wireName,
        'void_reason': voidReason,
        'voided_at': voidedAt?.toIso8601String(),
      };

  factory Expense.fromRow(Map<String, Object?> row) {
    final voidedAtRaw = row['voided_at'] as String?;
    return Expense(
      id: row['id'] as int?,
      name: row['name'] as String? ?? '',
      amount: (row['amount'] as int?) ?? 0,
      businessDate: row['business_date'] as String? ?? '',
      createdAt:
          DateTime.tryParse(row['created_at'] as String? ?? '') ?? DateTime.now(),
      paymentMethodId: row['payment_method_id'] as int?,
      paymentMethodName: row['payment_method_name'] as String? ?? '',
      status: ExpenseStatus.fromWire(row['status'] as String?),
      voidReason: row['void_reason'] as String?,
      voidedAt: voidedAtRaw == null ? null : DateTime.tryParse(voidedAtRaw),
    );
  }
}
