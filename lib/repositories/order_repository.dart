import 'dart:math';

import 'package:sqflite/sqflite.dart';

import '../core/app_date.dart';
import '../core/app_exception.dart';
import '../data/db/app_database.dart';
import '../data/models/order.dart';
import '../data/models/order_line.dart';
import '../data/models/payment_method.dart';

/// An order together with its lines, as the history and export screens need it.
class OrderWithLines {
  const OrderWithLines(this.order, this.lines);

  final Order order;
  final List<OrderLine> lines;

  int get lineCount => lines.length;
  int get itemCount => lines.fold(0, (sum, line) => sum + line.qty);
}

/// A product plus quantity, staged in the cart before the sale is committed.
class DraftLine {
  const DraftLine({
    required this.productId,
    required this.productName,
    required this.unitPrice,
    required this.qty,
  });

  final int? productId;
  final String productName;
  final int unitPrice;
  final int qty;

  int get lineTotal => qty * unitPrice;
}

/// Shared by every sample draw, so two draws in a row differ.
final Random _sampleRandom = Random();

/// Order creation, history and voiding.
class OrderRepository {
  OrderRepository(this._database);

  final AppDatabase _database;

  Database get _db => _database.db;

  /// Commits a cart as a single order.
  ///
  /// Everything happens in one transaction: the per-day label, the order row
  /// and every line. A crash mid-sale leaves no half-written order behind.
  Future<Order> createOrder({
    required List<DraftLine> lines,
    required PaymentMethod paymentMethod,
    DateTime? now,
  }) async {
    if (lines.isEmpty) {
      throw const ValidationException('Add at least one item before paying.');
    }
    for (final line in lines) {
      if (line.qty <= 0) {
        throw ValidationException(
          'Quantity for ${line.productName} must be at least 1.',
        );
      }
    }

    final moment = now ?? DateTime.now();
    final businessDate = formatIsoDate(moment);
    final total = lines.fold(0, (sum, line) => sum + line.lineTotal);

    return _database.transaction(
      (txn) async {
        // The label staff quote is a per-day counter, so it restarts at 1 each
        // morning and stays short. It is derived inside the transaction so two
        // quick sales cannot collide on the same number.
        final label = await _nextOrderLabel(txn, businessDate);

        final order = Order(
          id: null,
          orderLabel: label,
          businessDate: businessDate,
          createdAt: moment,
          paymentMethodId: paymentMethod.id,
          // Snapshotted for the same reason as product name: a later rename
          // must not rewrite what this sale recorded.
          paymentMethodName: paymentMethod.name,
          status: OrderStatus.normal,
          total: total,
        );

        final orderId = await txn.insert('orders', order.toRow()..remove('id'));

        for (var index = 0; index < lines.length; index++) {
          final line = lines[index];
          await txn.insert('order_lines', {
            'order_id': orderId,
            'product_id': line.productId,
            'product_name': line.productName,
            'qty': line.qty,
            'unit_price': line.unitPrice,
            'line_total': line.lineTotal,
            'line_no': index,
          });
        }

        return order.copyWith(id: orderId);
      },
      failureMessage: 'Could not save the sale. Nothing was recorded — '
          'please ring it up again.',
    );
  }

  Future<String> _nextOrderLabel(Transaction txn, String businessDate) async {
    final rows = await txn.rawQuery(
      'SELECT COUNT(*) AS c FROM orders WHERE business_date = ?',
      [businessDate],
    );
    final count = Sqflite.firstIntValue(rows) ?? 0;
    return (count + 1).toString();
  }

  /// Marks [orderId] voided, keeping the row and its lines intact.
  ///
  /// The reason and timestamp are the audit trail: the Excel export carries the
  /// reason into the `Notes` column so the day can be reconciled on paper.
  Future<Order> voidOrder({
    required int orderId,
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
          'orders',
          where: 'id = ?',
          whereArgs: [orderId],
          limit: 1,
        );
        if (rows.isEmpty) {
          throw const NotFoundException('That order no longer exists.');
        }

        final existing = Order.fromRow(rows.first);
        if (existing.isVoided) {
          throw const ConflictException('That order is already voided.');
        }

        await txn.update(
          'orders',
          {
            'status': OrderStatus.voided.wireName,
            'void_reason': trimmed,
            'voided_at': moment.toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [orderId],
        );

        return existing.copyWith(
          status: OrderStatus.voided,
          voidReason: trimmed,
          voidedAt: moment,
        );
      },
      failureMessage: 'Could not void the order.',
    );
  }

  /// Orders for [date], newest first — the history screen's default view.
  Future<List<OrderWithLines>> ordersForDate(DateTime date) =>
      ordersInRange(from: date, to: date);

  /// Share of a day's orders returned by [sampleOrdersForDate].
  static const double sampleFraction = 0.45;

  /// A random 45% of the orders on [date].
  ///
  /// Read-only, like every other history query: the draw happens in memory
  /// over what [ordersForDate] returned, so opening the sample never touches a
  /// row. Nothing about which orders were drawn is stored either — each call
  /// is a fresh draw.
  ///
  /// The sample size is 45% of the day rounded to the nearest order, but never
  /// zero while the day has any: a two-sale morning would otherwise sample to
  /// nothing and read as a day with no business. The drawn orders keep their
  /// chronological position, so the page reads like the history it samples.
  ///
  /// Pass [random] to make the draw reproducible in tests.
  Future<List<OrderWithLines>> sampleOrdersForDate(
    DateTime date, {
    Random? random,
  }) async {
    final all = await ordersForDate(date);
    if (all.isEmpty) return const [];

    final size = max(1, (all.length * sampleFraction).round());

    // Drawing indices rather than orders keeps the restore to chronological
    // order a plain sort, with no comparator over orders.
    final indices = List<int>.generate(all.length, (index) => index)
      ..shuffle(random ?? _sampleRandom);
    final drawn = indices.take(size).toList()..sort();

    return drawn.map((index) => all[index]).toList(growable: false);
  }

  /// Orders with `business_date` between [from] and [to] inclusive.
  ///
  /// Loads lines for the whole range in one extra query rather than one per
  /// order, so a month-long export stays two round trips.
  Future<List<OrderWithLines>> ordersInRange({
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
      final orderRows = await _db.query(
        'orders',
        where: 'business_date BETWEEN ? AND ?',
        whereArgs: [fromIso, toIso],
        orderBy: 'business_date ASC, created_at ASC, id ASC',
      );
      if (orderRows.isEmpty) return const [];

      final orders = orderRows.map(Order.fromRow).toList(growable: false);
      final ids = orders.map((o) => o.id).whereType<int>().toList();

      final placeholders = List.filled(ids.length, '?').join(', ');
      final lineRows = await _db.query(
        'order_lines',
        where: 'order_id IN ($placeholders)',
        whereArgs: ids,
        orderBy: 'order_id ASC, line_no ASC, id ASC',
      );

      final linesByOrder = <int, List<OrderLine>>{};
      for (final row in lineRows) {
        final line = OrderLine.fromRow(row);
        final orderId = line.orderId;
        if (orderId == null) continue;
        linesByOrder.putIfAbsent(orderId, () => <OrderLine>[]).add(line);
      }

      return orders
          .map((order) => OrderWithLines(
                order,
                linesByOrder[order.id] ?? const <OrderLine>[],
              ))
          .toList(growable: false);
    } on DatabaseException catch (error) {
      throw StorageException('Could not load order history.', cause: error);
    }
  }

  /// Headline figures for the day, shown on the back-office landing screen.
  ///
  /// Voided orders are excluded from money and counts, matching how the Excel
  /// `Day Summary` sheet totals a day.
  Future<DayTotals> totalsForDate(DateTime date) async {
    final iso = formatIsoDate(date);
    try {
      final rows = await _db.rawQuery(
        '''
        SELECT
          COUNT(*)                AS order_count,
          COALESCE(SUM(total), 0) AS revenue
        FROM orders
        WHERE business_date = ? AND status = 'normal'
        ''',
        [iso],
      );
      final voidRows = await _db.rawQuery(
        '''
        SELECT COUNT(*) AS c FROM orders
        WHERE business_date = ? AND status = 'voided'
        ''',
        [iso],
      );

      final row = rows.first;
      return DayTotals(
        date: startOfDay(date),
        orderCount: (row['order_count'] as int?) ?? 0,
        revenue: (row['revenue'] as int?) ?? 0,
        voidedCount: Sqflite.firstIntValue(voidRows) ?? 0,
      );
    } on DatabaseException catch (error) {
      throw StorageException("Could not load today's totals.", cause: error);
    }
  }
}

/// Aggregate figures for one business day.
class DayTotals {
  const DayTotals({
    required this.date,
    required this.orderCount,
    required this.revenue,
    required this.voidedCount,
  });

  final DateTime date;
  final int orderCount;
  final int revenue;
  final int voidedCount;
}
