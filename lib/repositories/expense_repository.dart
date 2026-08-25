import 'package:sqflite/sqflite.dart';

import '../core/app_date.dart';
import '../core/app_exception.dart';
import '../data/db/app_database.dart';
import '../data/models/expense.dart';
import '../data/models/payment_method.dart';

/// Expense recording, browsing and voiding.
///
/// The sibling of `OrderRepository`, and deliberately shaped like it: an
/// expense is stamped the same way a sale is, snapshots its payment method the
/// same way, and is voided rather than deleted for the same reason — the books
/// have to explain themselves months later.
class ExpenseRepository {
  ExpenseRepository(this._database);

  final AppDatabase _database;

  Database get _db => _database.db;

  /// Records one expense.
  ///
  /// [now] is the moment it is stamped with; leave it null for an expense
  /// entered as it happens, and pass a moment to backdate one that was paid
  /// earlier — exactly how the payment sheet hands a hand-set stamp to
  /// `OrderRepository.createOrder`.
  Future<Expense> createExpense({
    required String name,
    required int amount,
    required PaymentMethod paymentMethod,
    DateTime? now,
  }) async {
    final moment = now ?? DateTime.now();

    final expense = Expense(
      id: null,
      name: name.trim(),
      amount: amount,
      businessDate: formatIsoDate(moment),
      createdAt: moment,
      paymentMethodId: paymentMethod.id,
      // Snapshotted for the same reason an order does it: a later rename must
      // not rewrite what this expense recorded.
      paymentMethodName: paymentMethod.name,
      status: ExpenseStatus.normal,
    );
    expense.validate();

    try {
      final id = await _db.insert('expenses', expense.toRow()..remove('id'));
      return expense.copyWith(id: id);
    } on DatabaseException catch (error) {
      throw StorageException(
        'Could not save the expense. Nothing was recorded — please enter it '
        'again.',
        cause: error,
      );
    }
  }

  /// Expenses recorded against [date], oldest first.
  Future<List<Expense>> expensesForDate(DateTime date) =>
      expensesInRange(from: date, to: date);

  /// Expenses with `business_date` between [from] and [to] inclusive.
  Future<List<Expense>> expensesInRange({
    required DateTime from,
    required DateTime to,
  }) async {
    final fromIso = formatIsoDate(from);
    final toIso = formatIsoDate(to);
    if (toIso.compareTo(fromIso) < 0) {
      throw const ValidationException(
        'The end date must not be before the start date.',
      );
    }

    try {
      final rows = await _db.query(
        'expenses',
        where: 'business_date BETWEEN ? AND ?',
        whereArgs: [fromIso, toIso],
        orderBy: 'business_date ASC, created_at ASC, id ASC',
      );
      return rows.map(Expense.fromRow).toList(growable: false);
    } on DatabaseException catch (error) {
      throw StorageException('Could not load expenses.', cause: error);
    }
  }

  /// Marks [expenseId] voided, keeping the row intact.
  ///
  /// The reason and timestamp are the audit trail; the export carries the
  /// reason into the `Notes` column, as it does for a voided sale.
  Future<Expense> voidExpense({
    required int expenseId,
    required String reason,
    DateTime? now,
  }) async {
    final trimmed = reason.trim();
    if (trimmed.isEmpty) {
      throw const ValidationException('A void needs a reason.');
    }
    if (trimmed.length > 200) {
      throw const ValidationException(
        'Void reason is too long (200 characters maximum).',
      );
    }

    final moment = now ?? DateTime.now();

    return _database.transaction(
      (txn) async {
        final rows = await txn.query(
          'expenses',
          where: 'id = ?',
          whereArgs: [expenseId],
          limit: 1,
        );
        if (rows.isEmpty) {
          throw const NotFoundException('That expense no longer exists.');
        }

        final existing = Expense.fromRow(rows.first);
        if (existing.isVoided) {
          throw const ConflictException('That expense is already voided.');
        }

        await txn.update(
          'expenses',
          {
            'status': ExpenseStatus.voided.wireName,
            'void_reason': trimmed,
            'voided_at': moment.toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [expenseId],
        );

        return existing.copyWith(
          status: ExpenseStatus.voided,
          voidReason: trimmed,
          voidedAt: moment,
        );
      },
      failureMessage: 'Could not void the expense.',
    );
  }

  /// Headline figures for one day.
  ///
  /// Voided expenses are excluded from the money and the count, matching how a
  /// day's sales are totalled.
  Future<ExpenseDayTotals> totalsForDate(DateTime date) async {
    final iso = formatIsoDate(date);
    try {
      final rows = await _db.rawQuery(
        '''
        SELECT
          COUNT(*)                 AS expense_count,
          COALESCE(SUM(amount), 0) AS spend
        FROM expenses
        WHERE business_date = ? AND status = 'normal'
        ''',
        [iso],
      );
      final voidRows = await _db.rawQuery(
        '''
        SELECT COUNT(*) AS c FROM expenses
        WHERE business_date = ? AND status = 'voided'
        ''',
        [iso],
      );

      final row = rows.first;
      return ExpenseDayTotals(
        date: startOfDay(date),
        expenseCount: (row['expense_count'] as int?) ?? 0,
        spend: (row['spend'] as int?) ?? 0,
        voidedCount: Sqflite.firstIntValue(voidRows) ?? 0,
      );
    } on DatabaseException catch (error) {
      throw StorageException(
        "Could not load the day's expense totals.",
        cause: error,
      );
    }
  }
}

/// Aggregate expense figures for one business day.
class ExpenseDayTotals {
  const ExpenseDayTotals({
    required this.date,
    required this.expenseCount,
    required this.spend,
    required this.voidedCount,
  });

  final DateTime date;
  final int expenseCount;

  /// Whole RWF paid out on the day, voided rows excluded.
  final int spend;

  final int voidedCount;
}
