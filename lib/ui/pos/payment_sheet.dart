import 'package:flutter/material.dart';

import '../../core/app_date.dart';
import '../../core/money.dart';
import '../../data/models/payment_method.dart';
import '../theme.dart';
import '../widgets/stamp_row.dart';
import 'sale_date_dialog.dart';
import 'time_pad_dialog.dart';

/// What the payment sheet resolves to.
class PaymentChoice {
  const PaymentChoice({
    required this.method,
    this.at,
    this.isDateCustom = false,
    this.isTimeCustom = false,
  });

  final PaymentMethod method;

  /// The moment the cashier set by hand, or `null` when they left both the date
  /// and the clock alone — in which case the sale is stamped when it is written
  /// rather than when the sheet happened to open.
  final DateTime? at;

  /// The sale was dated to an earlier day than today.
  final bool isDateCustom;

  /// The clock was moved off the current time.
  final bool isTimeCustom;
}

/// Payment step: pick a method and the sale is committed.
///
/// Choosing the method *is* the confirmation — there is no second "confirm"
/// button. That keeps a one-item sale at three taps (product → Charge →
/// method) while leaving the amount large and legible for the read-back. The
/// date and time rows above the methods are optional: both default to now, so
/// they cost nothing on the sales that do not need them.
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
  /// The clock reading shown while nothing has been set by hand. It does not
  /// tick — it is only ever a preview, since a sale left on the clock is
  /// stamped by the repository at write time — but it is re-read whenever the
  /// cashier hands the sale back to the clock, so the rows never show a
  /// reading older than their last touch of them.
  DateTime _clockTime = DateTime.now();

  /// The two halves are held apart on purpose. Backdating a sale and correcting
  /// its clock are separate corrections, and either can be undone without
  /// disturbing the other.
  DateTime? _customDate;
  DateTime? _customTime;

  DateTime get _effectiveDate => _customDate ?? startOfDay(_clockTime);

  /// What the sale will be stamped with if it is confirmed now.
  DateTime get _effectiveMoment {
    final clock = _customTime ?? _clockTime;
    return combineDateAndTime(_effectiveDate, clock.hour, clock.minute);
  }

  /// The stamp to hand the repository: `null` while both halves are still on
  /// the clock, so an ordinary sale is still timed at the moment it is written.
  DateTime? get _explicitStamp =>
      _customDate == null && _customTime == null ? null : _effectiveMoment;

  void _useClock() {
    setState(() {
      _clockTime = DateTime.now();
      _customTime = null;
    });
  }

  void _useToday() {
    setState(() {
      _clockTime = DateTime.now();
      _customDate = null;
    });
  }

  Future<void> _editDate() async {
    final today = startOfDay(DateTime.now());
    final picked = await SaleDateDialog.show(
      context,
      today: today,
      initial: _effectiveDate,
    );
    if (picked == null || !mounted) return;

    // Landing back on today means nothing was really overridden, so let the
    // sale follow the clock again — the same rule the time pad uses.
    setState(() => _customDate = isSameDate(picked, today) ? null : picked);
  }

  Future<void> _editTime() async {
    final picked = await TimePadDialog.show(
      context,
      day: _effectiveDate,
      initial: TimeOfDay.fromDateTime(_effectiveMoment),
    );
    if (picked == null || !mounted) return;

    // Landing on the current minute — usually via the pad's own "Now" — means
    // they did not really override anything, so keep the clock half on the
    // clock. The chosen date is separate state and survives this.
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
        // Scrollable because the sheet now carries two stamp rows as well as
        // one button per payment method: a shop that adds a fourth or fifth
        // method, on a short viewport, would otherwise overflow the column.
        child: SingleChildScrollView(
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
              StampRow(
                icon: Icons.event_outlined,
                label: 'Sale date',
                customLabel: 'Sale date (backdated)',
                value: formatRelativeDate(
                  _effectiveDate,
                  today: startOfDay(_clockTime),
                ),
                isCustom: _customDate != null,
                onEdit: _editDate,
                onReset: _useToday,
                resetTooltip: 'Back to today',
              ),
              const SizedBox(height: 10),
              StampRow(
                icon: Icons.schedule,
                label: 'Sale time',
                customLabel: 'Sale time (edited)',
                value: formatHourMinute(_effectiveMoment),
                isCustom: _customTime != null,
                onEdit: _editTime,
                onReset: _useClock,
                resetTooltip: 'Back to the current time',
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
                          PaymentChoice(
                            method: method,
                            at: _explicitStamp,
                            isDateCustom: _customDate != null,
                            isTimeCustom: _customTime != null,
                          ),
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
      ),
    );
  }
}
