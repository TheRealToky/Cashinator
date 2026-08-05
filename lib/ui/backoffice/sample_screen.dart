import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_date.dart';
import '../../core/app_exception.dart';
import '../../core/money.dart';
import '../../repositories/order_repository.dart';
import '../widgets/async_value_view.dart';
import 'order_views.dart';

/// A spot-check view of a day's sales: the same list as Order history, cut
/// down to a random 45% of that day's orders.
///
/// Read-only by design. Nothing here writes to the database — not the orders
/// it shows, and not the draw itself, which is made fresh in memory each time
/// the page loads. Voiding stays on Order history, where the full day is
/// visible and a decision can be made in context.
class SampleScreen extends StatefulWidget {
  const SampleScreen({super.key});

  @override
  State<SampleScreen> createState() => _SampleScreenState();
}

class _SampleScreenState extends State<SampleScreen> {
  DateTime _date = startOfDay(DateTime.now());
  List<OrderWithLines> _sample = const [];
  int _dayOrderCount = 0;
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
      final repository = context.read<OrderRepository>();
      // The day's total is read alongside the draw so the header can say what
      // the 45% was taken out of.
      final total = (await repository.ordersForDate(_date)).length;
      final sample = await repository.sampleOrdersForDate(_date);

      if (!mounted) return;
      setState(() {
        // Newest first, matching Order history.
        _sample = sample.reversed.toList(growable: false);
        _dayOrderCount = total;
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sample'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: OutlinedButton.icon(
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.shuffle),
              label: const Text('Draw again'),
            ),
          ),
        ],
      ),
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
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const LoadingView()
                : _error != null
                    ? ErrorView(message: _error!, onRetry: _load)
                    : _sample.isEmpty
                        ? const EmptyView(
                            icon: Icons.shuffle,
                            message: 'No orders on this day to sample.',
                          )
                        : Column(
                            children: [
                              _SampleSummary(
                                sample: _sample,
                                dayOrderCount: _dayOrderCount,
                              ),
                              const Divider(height: 1),
                              Expanded(
                                // Virtualised like the history list: a sample
                                // of a busy day is still a long list.
                                child: ListView.separated(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 8),
                                  itemCount: _sample.length,
                                  separatorBuilder: (_, __) =>
                                      const Divider(height: 1),
                                  itemBuilder: (context, index) =>
                                      OrderTile(entry: _sample[index]),
                                ),
                              ),
                            ],
                          ),
          ),
        ],
      ),
    );
  }
}

/// Says what the list below is and what it was drawn from, so the figures are
/// never mistaken for the day's real totals.
class _SampleSummary extends StatelessWidget {
  const _SampleSummary({required this.sample, required this.dayOrderCount});

  final List<OrderWithLines> sample;
  final int dayOrderCount;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final percent =
        (OrderRepository.sampleFraction * 100).round().toString();

    // Voided orders are shown but carry no money, exactly as on the day's
    // real totals.
    final sampledRevenue = sample
        .where((entry) => !entry.order.isVoided)
        .fold(0, (sum, entry) => sum + entry.order.total);

    return Container(
      width: double.infinity,
      color: scheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${sample.length} of $dayOrderCount order'
            '${dayOrderCount == 1 ? '' : 's'} · '
            '${formatRwfWithUnit(sampledRevenue)} in this sample',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            'A random $percent% of this day, redrawn every time. Not the '
            "day's totals — use Order history or the Excel export for those.",
            style: TextStyle(fontSize: 15, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
