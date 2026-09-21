import 'package:sqflite/sqflite.dart';

import '../core/app_date.dart';
import '../core/app_exception.dart';
import '../data/db/app_database.dart';
import '../data/models/production_log.dart';

/// Writes, reads and summarises production logs.
///
/// Shaped after [ExpenseRepository]: all writes go through a transaction, rows
/// are never deleted (there is no voiding for production, but the pattern keeps
/// the door open for it), and range queries use the indexed `business_date`
/// column exactly as expenses do.
class ProductionRepository {
  ProductionRepository(this._database);

  final AppDatabase _database;

  Database get _db => _database.db;

  /// Records a production session: all [lines] with the same [recordedAt]
  /// timestamp are inserted in one transaction.
  ///
  /// Lines with qty ≤ 0 are silently skipped — the UI already prevents them,
  /// but the repository is the last gate.
  Future<void> recordSession(List<ProductionLog> lines) async {
    final nonZero = lines.where((l) => l.qty > 0).toList();
    if (nonZero.isEmpty) {
      throw const ValidationException(
        'Record at least one product with a quantity above zero.',
      );
    }

    await _database.transaction(
      (txn) async {
        for (final line in nonZero) {
          await txn.insert(
            'production_logs',
            line.toRow()..remove('id'),
          );
        }
      },
      failureMessage: 'Could not save the production session.',
    );
  }

  /// All logs recorded against [date], newest session first.
  Future<List<ProductionLog>> logsForDate(DateTime date) =>
      logsInRange(from: date, to: date);

  /// Logs with `business_date` between [from] and [to] inclusive,
  /// ordered by date then by session time then by id.
  Future<List<ProductionLog>> logsInRange({
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
        'production_logs',
        where: 'business_date BETWEEN ? AND ?',
        whereArgs: [fromIso, toIso],
        orderBy: 'business_date ASC, recorded_at ASC, id ASC',
      );
      return rows.map(ProductionLog.fromRow).toList(growable: false);
    } on DatabaseException catch (error) {
      throw StorageException('Could not load production logs.', cause: error);
    }
  }

  /// Headline figures for one day.
  Future<ProductionDayTotals> totalsForDate(DateTime date) async {
    final iso = formatIsoDate(date);
    try {
      final rows = await _db.rawQuery(
        '''
        SELECT
          COUNT(*)                     AS item_count,
          COALESCE(SUM(qty), 0)        AS total_qty,
          COALESCE(SUM(qty * unit_price), 0) AS total_value
        FROM production_logs
        WHERE business_date = ?
        ''',
        [iso],
      );
      final row = rows.first;
      return ProductionDayTotals(
        date: startOfDay(date),
        itemCount: (row['item_count'] as int?) ?? 0,
        totalQty: (row['total_qty'] as int?) ?? 0,
        totalValue: (row['total_value'] as int?) ?? 0,
      );
    } on DatabaseException catch (error) {
      throw StorageException(
        "Could not load the day's production totals.",
        cause: error,
      );
    }
  }
}
