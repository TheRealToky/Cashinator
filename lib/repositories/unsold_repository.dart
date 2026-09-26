import 'package:sqflite/sqflite.dart';

import '../core/app_date.dart';
import '../core/app_exception.dart';
import '../data/db/app_database.dart';
import '../data/models/unsold_log.dart';

/// Writes, reads and summarises unsold logs.
///
/// Shaped after [ProductionRepository]: all writes go through a transaction,
/// rows are inserted with session timestamps, and range queries use the indexed
/// `business_date` column.
class UnsoldRepository {
  UnsoldRepository(this._database);

  final AppDatabase _database;

  Database get _db => _database.db;

  /// Records an unsold session: all [lines] with the same [recordedAt]
  /// timestamp are inserted in one transaction.
  ///
  /// Lines with qty ≤ 0 are skipped.
  Future<void> recordSession(List<UnsoldLog> lines) async {
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
            'unsold_logs',
            line.toRow()..remove('id'),
          );
        }
      },
      failureMessage: 'Could not save the unsold session.',
    );
  }

  /// All logs recorded against [date], newest session first.
  Future<List<UnsoldLog>> logsForDate(DateTime date) =>
      logsInRange(from: date, to: date);

  /// Logs with `business_date` between [from] and [to] inclusive,
  /// ordered by date then by session time then by id.
  Future<List<UnsoldLog>> logsInRange({
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
        'unsold_logs',
        where: 'business_date BETWEEN ? AND ?',
        whereArgs: [fromIso, toIso],
        orderBy: 'business_date ASC, recorded_at ASC, id ASC',
      );
      return rows.map(UnsoldLog.fromRow).toList(growable: false);
    } on DatabaseException catch (error) {
      throw StorageException('Could not load unsold logs.', cause: error);
    }
  }

  /// Headline figures for one day.
  Future<UnsoldDayTotals> totalsForDate(DateTime date) async {
    final iso = formatIsoDate(date);
    try {
      final rows = await _db.rawQuery(
        '''
        SELECT
          COUNT(*)                     AS item_count,
          COALESCE(SUM(qty), 0)        AS total_qty,
          COALESCE(SUM(qty * unit_price), 0) AS total_value
        FROM unsold_logs
        WHERE business_date = ?
        ''',
        [iso],
      );
      final row = rows.first;
      return UnsoldDayTotals(
        date: startOfDay(date),
        itemCount: (row['item_count'] as int?) ?? 0,
        totalQty: (row['total_qty'] as int?) ?? 0,
        totalValue: (row['total_value'] as int?) ?? 0,
      );
    } on DatabaseException catch (error) {
      throw StorageException(
        "Could not load the day's unsold totals.",
        cause: error,
      );
    }
  }
}
