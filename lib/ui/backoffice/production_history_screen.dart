import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_date.dart';
import '../../core/app_exception.dart';
import '../../core/money.dart';
import '../../data/models/production_log.dart';
import '../../repositories/production_repository.dart';
import '../widgets/async_value_view.dart';
import 'order_views.dart';

/// One recording session containing one or more [ProductionLog] entries.
class ProductionSession {
  const ProductionSession({
    required this.recordedAt,
    required this.lines,
  });

  final DateTime recordedAt;
  final List<ProductionLog> lines;

  String get timeLabel => formatHourMinute(recordedAt);
  int get totalQty => lines.fold(0, (sum, l) => sum + l.qty);
  int get totalValue => lines.fold(0, (sum, l) => sum + l.lineValue);
  int get itemCount => lines.length;

  /// Groups raw [logs] by their [recordedAt] timestamp, newest session first.
  static List<ProductionSession> group(List<ProductionLog> logs) {
    final map = <DateTime, List<ProductionLog>>{};
    for (final log in logs) {
      map.putIfAbsent(log.recordedAt, () => []).add(log);
    }
    final sessions = map.entries
        .map((e) => ProductionSession(recordedAt: e.key, lines: e.value))
        .toList();
    sessions.sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
    return sessions;
  }
}

/// Browse a day's kitchen production records.
///
/// Looks and behaves like [OrderHistoryScreen]: a date bar with back/forward
/// navigation at the top, and an expandable list of production sessions below.
class ProductionHistoryScreen extends StatefulWidget {
  const ProductionHistoryScreen({super.key});

  @override
  State<ProductionHistoryScreen> createState() =>
      _ProductionHistoryScreenState();
}

class _ProductionHistoryScreenState extends State<ProductionHistoryScreen> {
  DateTime _date = startOfDay(DateTime.now());
  List<ProductionSession> _sessions = const [];
  ProductionDayTotals? _totals;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final repo = context.read<ProductionRepository>();
      final logs = await repo.logsForDate(_date);
      final totals = await repo.totalsForDate(_date);

      if (!mounted) return;
      setState(() {
        _sessions = ProductionSession.group(logs);
        _totals = totals;
        _loading = false;
      });
    } on AppException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _loading = false;
      });
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked == null || !mounted) return;

    setState(() => _date = startOfDay(picked));
    await _load();
  }

  void _shiftDay(int days) {
    setState(() => _date = startOfDay(_date.add(Duration(days: days))));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final totals = _totals;

    return Scaffold(
      appBar: AppBar(title: const Text('Production history')),
      body: Column(
        children: [
          OrderDateBar(
            date: _date,
            onPrevious: () => _shiftDay(-1),
            onNext: startOfDay(DateTime.now()).isAfter(_date)
                ? () => _shiftDay(1)
                : null,
            onPick: _pickDate,
          ),
          if (!_loading && _error == null && totals != null && totals.totalQty > 0) ...[
            _ProductionDaySummaryBar(totals: totals),
          ],
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const LoadingView()
                : _error != null
                    ? ErrorView(message: _error!, onRetry: _load)
                    : _sessions.isEmpty
                        ? const EmptyView(
                            icon: Icons.inventory_2_outlined,
                            message: 'No production recorded on this day.',
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            itemCount: _sessions.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) =>
                                _ProductionSessionTile(
                              session: _sessions[index],
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}

/// Compact bar summarizing the day's total produced units and total value.
class _ProductionDaySummaryBar extends StatelessWidget {
  const _ProductionDaySummaryBar({required this.totals});

  final ProductionDayTotals totals;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
      child: Row(
        children: [
          Icon(Icons.inventory_2_outlined, size: 20, color: scheme.primary),
          const SizedBox(width: 8),
          Text(
            'Total: ${totals.totalQty} unit${totals.totalQty == 1 ? '' : 's'} produced '
            '(${totals.itemCount} line${totals.itemCount == 1 ? '' : 's'})',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: scheme.onSurface,
            ),
          ),
          const Spacer(),
          Text(
            formatRwfWithUnit(totals.totalValue),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: scheme.primary,
            ),
          ),
        ],
      ),
    );
  }
}

/// One production session tile, expanding to show product lines.
class _ProductionSessionTile extends StatelessWidget {
  const _ProductionSessionTile({required this.session});

  final ProductionSession session;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return ExpansionTile(
      tilePadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      childrenPadding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
      title: Row(
        children: [
          Text(
            'Session at ${session.timeLabel}',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: scheme.onSurface,
            ),
          ),
          const Spacer(),
          Text(
            formatRwfWithUnit(session.totalValue),
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: scheme.onSurface,
            ),
          ),
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          '${session.timeLabel} · ${session.itemCount} item${session.itemCount == 1 ? '' : 's'} · '
          '${session.totalQty} unit${session.totalQty == 1 ? '' : 's'}',
          style: TextStyle(fontSize: 15, color: scheme.onSurfaceVariant),
        ),
      ),
      children: [
        for (final line in session.lines)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                SizedBox(
                  width: 48,
                  child: Text(
                    '${line.qty}×',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        line.productName,
                        style: const TextStyle(fontSize: 16),
                      ),
                      if (line.category != null && line.category!.isNotEmpty)
                        Text(
                          line.category!,
                          style: TextStyle(
                            fontSize: 13,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                Text(
                  formatRwf(line.lineValue),
                  style: const TextStyle(fontSize: 16),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
