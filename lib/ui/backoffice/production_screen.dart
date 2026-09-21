import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_date.dart';
import '../../core/app_exception.dart';
import '../../core/money.dart';
import '../../data/models/product.dart';
import '../../data/models/production_log.dart';
import '../../repositories/product_repository.dart';
import '../../repositories/production_repository.dart';
import '../widgets/async_value_view.dart';

/// Records how many units of each product the kitchen produced in one session.
///
/// Design:
///  • Lists every **active** product (same filtered set the till uses), each
///    with a [–] / [+] counter. Staff tap to count what came out of the oven.
///  • Top-right "Set date & time" button lets the manager backdate a session
///    if it wasn't logged in real time.
///  • "Save session" (bottom) inserts all non-zero lines in one transaction
///    and resets the counters.
class ProductionScreen extends StatefulWidget {
  const ProductionScreen({super.key});

  @override
  State<ProductionScreen> createState() => _ProductionScreenState();
}

class _ProductionScreenState extends State<ProductionScreen> {
  List<Product> _products = const [];
  bool _loading = true;
  bool _saving = false;
  String? _error;

  /// One counter entry per product id.
  final Map<int, int> _counts = {};

  /// The session datetime — defaults to now, can be overridden by the
  /// date/time picker.
  late DateTime _sessionAt;
  bool _isDateTimeCustom = false;

  @override
  void initState() {
    super.initState();
    _sessionAt = DateTime.now();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final products =
          await context.read<ProductRepository>().activeProducts();
      if (!mounted) return;
      setState(() {
        _products = products;
        _loading = false;
        // Initialise counters for any new product that didn't have one yet.
        for (final p in products) {
          if (p.id != null) _counts.putIfAbsent(p.id!, () => 0);
        }
      });
    } on AppException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _loading = false;
      });
    }
  }

  void _increment(int productId) =>
      setState(() => _counts[productId] = (_counts[productId] ?? 0) + 1);

  void _decrement(int productId) => setState(() {
        final current = _counts[productId] ?? 0;
        if (current > 0) _counts[productId] = current - 1;
      });

  int get _nonZeroCount =>
      _counts.values.where((v) => v > 0).length;

  Future<void> _pickDateTime() async {
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _sessionAt,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (pickedDate == null || !mounted) return;

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_sessionAt),
    );
    if (pickedTime == null || !mounted) return;

    setState(() {
      _sessionAt = DateTime(
        pickedDate.year,
        pickedDate.month,
        pickedDate.day,
        pickedTime.hour,
        pickedTime.minute,
      );
      _isDateTimeCustom = true;
    });
  }

  Future<void> _save() async {
    if (_nonZeroCount == 0) return;
    if (_saving) return;

    setState(() => _saving = true);

    try {
      // Stamp now unless the manager picked a custom time.
      final recordedAt = _isDateTimeCustom ? _sessionAt : DateTime.now();

      final lines = <ProductionLog>[];
      for (final product in _products) {
        final id = product.id;
        if (id == null) continue;
        final qty = _counts[id] ?? 0;
        if (qty <= 0) continue;

        lines.add(ProductionLog(
          id: null,
          productId: id,
          productName: product.name,
          category: product.category,
          unitPrice: product.price,
          qty: qty,
          businessDate: formatIsoDate(recordedAt),
          recordedAt: recordedAt,
        ));
      }

      await context.read<ProductionRepository>().recordSession(lines);
      if (!mounted) return;

      // Summarise for the snackbar.
      final totalQty = lines.fold<int>(0, (sum, l) => sum + l.qty);
      final totalValue = lines.fold<int>(0, (sum, l) => sum + l.lineValue);
      final timeLabel =
          _isDateTimeCustom ? ' at ${formatHourMinute(recordedAt)}' : '';
      final dateLabel = _isDateTimeCustom
          ? ' (${formatRelativeDate(
              startOfDay(recordedAt),
              today: startOfDay(DateTime.now()),
            )})'
          : '';

      showAppSnackBar(
        context,
        'Saved $totalQty item${totalQty == 1 ? '' : 's'} · '
        '${formatRwfWithUnit(totalValue)}$timeLabel$dateLabel.',
      );

      // Reset counters and session time.
      setState(() {
        for (final key in _counts.keys) {
          _counts[key] = 0;
        }
        _sessionAt = DateTime.now();
        _isDateTimeCustom = false;
      });
    } on AppException catch (error) {
      if (!mounted) return;
      showAppSnackBar(context, error.message, isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Record Production'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: OutlinedButton.icon(
              onPressed: _loading || _saving ? null : _pickDateTime,
              icon: const Icon(Icons.schedule_outlined),
              label: Text(
                _isDateTimeCustom
                    ? '${formatIsoDate(_sessionAt)} '
                        '${formatHourMinute(_sessionAt)}'
                    : 'Set date & time',
              ),
            ),
          ),
        ],
      ),
      body: _loading
          ? const LoadingView()
          : _error != null
              ? ErrorView(message: _error!, onRetry: _load)
              : _products.isEmpty
                  ? const EmptyView(
                      icon: Icons.inventory_2_outlined,
                      message: 'No active products found.\n'
                          'Add products in the Products screen first.',
                    )
                  : Column(
                      children: [
                        // Session info bar.
                        _SessionBar(
                          sessionAt: _sessionAt,
                          isCustom: _isDateTimeCustom,
                          nonZeroCount: _nonZeroCount,
                        ),
                        const Divider(height: 1),
                        Expanded(
                          child: ListView.separated(
                            padding:
                                const EdgeInsets.only(top: 8, bottom: 120),
                            itemCount: _products.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final product = _products[index];
                              final id = product.id;
                              if (id == null) return const SizedBox.shrink();
                              final qty = _counts[id] ?? 0;
                              return _ProductionRow(
                                product: product,
                                qty: qty,
                                onIncrement: () => _increment(id),
                                onDecrement: () => _decrement(id),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
      // Floating save button anchored to the bottom.
      bottomNavigationBar: _loading || _error != null
          ? null
          : SafeArea(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: SizedBox(
                  height: 60,
                  child: FilledButton.icon(
                    onPressed:
                        (_nonZeroCount > 0 && !_saving) ? _save : null,
                    icon: _saving
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 3,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.save_outlined, size: 26),
                    label: Text(
                      _saving
                          ? 'Saving…'
                          : _nonZeroCount == 0
                              ? 'Tap + to count products'
                              : 'Save session '
                                  '($_nonZeroCount '
                                  'product${_nonZeroCount == 1 ? '' : 's'})',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}

/// Thin bar above the list showing the current session datetime and item count.
class _SessionBar extends StatelessWidget {
  const _SessionBar({
    required this.sessionAt,
    required this.isCustom,
    required this.nonZeroCount,
  });

  final DateTime sessionAt;
  final bool isCustom;
  final int nonZeroCount;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      color: isCustom
          ? scheme.primaryContainer.withValues(alpha: 0.5)
          : scheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Row(
        children: [
          Icon(
            isCustom
                ? Icons.event_available_outlined
                : Icons.access_time_outlined,
            size: 20,
            color: isCustom ? scheme.primary : scheme.onSurfaceVariant,
          ),
          const SizedBox(width: 10),
          Text(
            isCustom
                ? 'Session: ${formatIsoDate(sessionAt)} '
                    'at ${formatHourMinute(sessionAt)}'
                : 'Session: now  ·  tap "Set date & time" to backdate',
            style: TextStyle(
              fontSize: 15,
              color: isCustom ? scheme.primary : scheme.onSurfaceVariant,
              fontWeight: isCustom ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
          const Spacer(),
          if (nonZeroCount > 0)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: scheme.primary,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '$nonZeroCount counted',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: scheme.onPrimary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// One product row with a [–] / qty / [+] counter.
class _ProductionRow extends StatelessWidget {
  const _ProductionRow({
    required this.product,
    required this.qty,
    required this.onIncrement,
    required this.onDecrement,
  });

  final Product product;
  final int qty;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasCount = qty > 0;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      color:
          hasCount ? scheme.primaryContainer.withValues(alpha: 0.25) : null,
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        title: Text(
          product.name,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: hasCount ? scheme.primary : scheme.onSurface,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            [
              formatRwfWithUnit(product.price),
              if (product.category != null && product.category!.isNotEmpty)
                product.category!,
            ].join(' · '),
            style: TextStyle(fontSize: 15, color: scheme.onSurfaceVariant),
          ),
        ),
        trailing: _Counter(
          qty: qty,
          onIncrement: onIncrement,
          onDecrement: onDecrement,
        ),
      ),
    );
  }
}

/// The [–] / [N] / [+] counter widget.
class _Counter extends StatelessWidget {
  const _Counter({
    required this.qty,
    required this.onIncrement,
    required this.onDecrement,
  });

  final int qty;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Decrement.
        SizedBox(
          width: 44,
          height: 44,
          child: Material(
            color: qty > 0
                ? scheme.errorContainer
                : scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: qty > 0 ? onDecrement : null,
              child: Icon(
                Icons.remove,
                size: 22,
                color: qty > 0
                    ? scheme.onErrorContainer
                    : scheme.onSurfaceVariant.withValues(alpha: 0.4),
              ),
            ),
          ),
        ),
        // Quantity display.
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 120),
          transitionBuilder: (child, animation) => ScaleTransition(
            scale: animation,
            child: child,
          ),
          child: SizedBox(
            key: ValueKey(qty),
            width: 52,
            child: Text(
              '$qty',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: qty > 0 ? scheme.primary : scheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
        // Increment.
        SizedBox(
          width: 44,
          height: 44,
          child: Material(
            color: scheme.primaryContainer,
            borderRadius: BorderRadius.circular(12),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onIncrement,
              child: Icon(
                Icons.add,
                size: 22,
                color: scheme.onPrimaryContainer,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
