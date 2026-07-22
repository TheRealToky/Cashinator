import 'package:flutter/material.dart';

import '../../core/app_date.dart';
import '../../core/money.dart';
import '../../data/models/payment_method.dart';
import '../theme.dart';
import 'time_pad_dialog.dart';

/// What the payment sheet resolves to.
class PaymentChoice {
  const PaymentChoice({required this.method, this.at});

  final PaymentMethod method;

  /// The time the cashier set by hand, or `null` when they kept the current
  /// time — in which case the sale is stamped when it is written rather than
  /// when the sheet happened to open.
  final DateTime? at;

  bool get isTimeCustom => at != null;
}

/// Payment step: pick a method and the sale is committed.
///
/// Choosing the method *is* the confirmation — there is no second "confirm"
/// button. That keeps a one-item sale at three taps (product → Charge →
/// method) while leaving the amount large and legible for the read-back. The
/// sale-time row above the methods is optional: it defaults to now, so it costs
/// nothing on the sales that do not need it.
class PaymentSheet extends StatefulWidget {
  const PaymentSheet({
    super.key,
    required this.total,
    required this.itemCount,
    required this.methods,
  });

  final int total;
  final int itemCount;
  final List<PaymentMethod> methods;

  /// Shows the sheet and resolves to the chosen method and time, or `null` if
  /// dismissed.
  static Future<PaymentChoice?> show(
    BuildContext context, {
    required int total,
    required int itemCount,
    required List<PaymentMethod> methods,
  }) {
    return showModalBottomSheet<PaymentChoice>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => PaymentSheet(
        total: total,
        itemCount: itemCount,
        methods: methods,
      ),
    );
  }

  @override
  State<PaymentSheet> createState() => _PaymentSheetState();
}

class _PaymentSheetState extends State<PaymentSheet> {
  /// The clock reading shown while no time has been set by hand. It does not
  /// tick — it is only ever a preview, since a sale left on the clock is
  /// stamped by the repository at write time — but it is re-read whenever the
  /// cashier hands the sale back to the clock, so the row never shows a
  /// reading older than their last touch of it.
  DateTime _clockTime = DateTime.now();

  DateTime? _customTime;

  DateTime get _effectiveTime => _customTime ?? _clockTime;

  void _useClock() {
    setState(() {
      _clockTime = DateTime.now();
      _customTime = null;
    });
  }

  Future<void> _editTime() async {
    final picked = await TimePadDialog.show(
      context,
      day: _clockTime,
      initial: TimeOfDay.fromDateTime(_effectiveTime),
    );
    if (picked == null || !mounted) return;

    // Landing on the current minute — usually via the pad's own "Now" — means
    // they did not really override anything, so keep the sale on the clock.
    if (formatHourMinute(picked) == formatHourMinute(DateTime.now())) {
      _useClock();
    } else {
      setState(() => _customTime = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 4, 28, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${widget.itemCount} item${widget.itemCount == 1 ? '' : 's'}',
              style: TextStyle(fontSize: 17, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 4),
            Text(
              formatRwfWithUnit(widget.total),
              style: TextStyle(
                fontSize: 42,
                fontWeight: FontWeight.w800,
                color: scheme.primary,
              ),
            ),
            const SizedBox(height: 20),
            _SaleTimeRow(
              time: _effectiveTime,
              isCustom: _customTime != null,
              onEdit: _editTime,
              onReset: _useClock,
            ),
            const SizedBox(height: 20),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'How is the customer paying?',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Wraps so a shop that adds a fourth or fifth method still gets
            // full-size buttons rather than a cramped row.
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final method in widget.methods)
                  SizedBox(
                    width: 200,
                    height: 84,
                    child: FilledButton.tonal(
                      onPressed: () => Navigator.of(context).pop(
                        PaymentChoice(method: method, at: _customTime),
                      ),
                      style: FilledButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Text(
                        method.name,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            SizedBox(
              height: AppTheme.minTapTarget,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Back to the cart'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The time this sale will be recorded at, and the way to change it.
///
/// An edited time is tinted and grows a reset button, so a mistyped time is
/// visible for the whole payment step rather than only in the history later.
class _SaleTimeRow extends StatelessWidget {
  const _SaleTimeRow({
    required this.time,
    required this.isCustom,
    required this.onEdit,
    required this.onReset,
  });

  final DateTime time;
  final bool isCustom;
  final VoidCallback onEdit;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: AppTheme.minTapTarget,
            child: OutlinedButton(
              onPressed: onEdit,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                alignment: Alignment.centerLeft,
                backgroundColor: isCustom ? scheme.tertiaryContainer : null,
                foregroundColor: isCustom
                    ? scheme.onTertiaryContainer
                    : scheme.onSurfaceVariant,
                side: BorderSide(
                  color: isCustom ? scheme.tertiary : scheme.outlineVariant,
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.schedule, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      isCustom ? 'Sale time (edited)' : 'Sale time',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    formatHourMinute(time),
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Icon(Icons.edit_outlined, size: 20),
                ],
              ),
            ),
          ),
        ),
        if (isCustom) ...[
          const SizedBox(width: 10),
          IconButton(
            onPressed: onReset,
            icon: const Icon(Icons.restore),
            iconSize: 26,
            tooltip: 'Back to the current time',
            style: IconButton.styleFrom(
              minimumSize: const Size(
                AppTheme.minTapTarget,
                AppTheme.minTapTarget,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
