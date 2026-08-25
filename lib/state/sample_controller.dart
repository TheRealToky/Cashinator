import '../core/app_date.dart';
import '../repositories/order_repository.dart';

/// One resolved sample, as the Sample screen renders it.
class SampleView {
  const SampleView({
    required this.orders,
    required this.dayOrderCount,
    required this.dayOrderCountAtDraw,
  });

  /// The drawn orders, chronological.
  final List<OrderWithLines> orders;

  /// Orders on the day right now — the "of 16" in the header.
  final int dayOrderCount;

  /// Orders on the day when this sample was drawn.
  final int dayOrderCountAtDraw;

  /// Sales rung up since the draw, which are therefore not in it.
  ///
  /// The till keeps selling while a draw is held, so without this the header
  /// reads like broken arithmetic: 7 of 20 is not 45% of anything.
  int get ordersSinceDraw => (dayOrderCount - dayOrderCountAtDraw).clamp(0, dayOrderCount);
}

/// Holds the Sample screen's draw for each business day.
///
/// The draw has to outlive the screen: a manager who samples a day, walks to
/// the till to check an order against the receipts, then reopens Sample must
/// find the same orders waiting — a fresh draw on every visit makes the
/// checking impossible. So a draw is kept until [redraw] is asked for.
///
/// It is kept as order ids, in memory, for as long as the app runs. Nothing is
/// written to the database: which orders someone happened to review is not a
/// fact about the shop's sales, and the records stay exactly as the till left
/// them.
///
/// Later sales are deliberately not added to a held draw. The sample is a
/// snapshot of the day as it stood, and [SampleView.ordersSinceDraw] tells the
/// screen how far the day has moved on.
class SampleController {
  SampleController(this._orders);

  final OrderRepository _orders;

  /// Business date (`YYYY-MM-DD`) to the ids drawn for it.
  final Map<String, _HeldDraw> _held = {};

  /// The sample for [date], drawing one only if none is being held.
  Future<SampleView> load(DateTime date) => _resolve(date, redraw: false);

  /// Throws away any held draw for [date] and draws a new one.
  Future<SampleView> redraw(DateTime date) => _resolve(date, redraw: true);

  /// Whether a draw is currently held for [date]. Test seam.
  bool isHolding(DateTime date) => _held.containsKey(formatIsoDate(date));

  Future<SampleView> _resolve(DateTime date, {required bool redraw}) async {
    final key = formatIsoDate(date);
    final all = await _orders.ordersForDate(date);

    if (!redraw) {
      final held = _held[key];
      if (held != null) {
        final kept = all
            .where((entry) => held.orderIds.contains(entry.order.id))
            .toList(growable: false);
        // An empty resolution means the held ids no longer match anything, so
        // there is nothing to keep stable — fall through to a fresh draw.
        if (kept.isNotEmpty) {
          return SampleView(
            orders: kept,
            dayOrderCount: all.length,
            dayOrderCountAtDraw: held.dayOrderCount,
          );
        }
      }
    }

    final drawn = _orders.drawSample(all);
    if (drawn.isEmpty) {
      // A day with no sales yet: hold nothing, so the first sale is sampled
      // rather than the screen staying empty until someone taps Draw again.
      _held.remove(key);
      return SampleView(
        orders: const [],
        dayOrderCount: all.length,
        dayOrderCountAtDraw: all.length,
      );
    }

    _held[key] = _HeldDraw(
      orderIds: drawn.map((entry) => entry.order.id).whereType<int>().toSet(),
      dayOrderCount: all.length,
    );

    return SampleView(
      orders: drawn,
      dayOrderCount: all.length,
      dayOrderCountAtDraw: all.length,
    );
  }
}

/// A draw being held for one day.
class _HeldDraw {
  const _HeldDraw({required this.orderIds, required this.dayOrderCount});

  final Set<int> orderIds;
  final int dayOrderCount;
}
