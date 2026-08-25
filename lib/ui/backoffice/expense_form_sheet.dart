import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_date.dart';
import '../../core/money.dart';
import '../../data/models/expense.dart';
import '../../data/models/payment_method.dart';
// The two stamp dialogs live under ui/pos because the till was the first thing
// to need them. They ask the same two questions here, so this form reuses them
// rather than growing a second pair that could drift.
import '../pos/sale_date_dialog.dart';
import '../pos/time_pad_dialog.dart';
import '../theme.dart';
import '../widgets/stamp_row.dart';

/// What the expense form resolves to: everything the repository needs to write
/// one row.
class ExpenseDraft {
  const ExpenseDraft({
    required this.name,
    required this.amount,
    required this.method,
    this.at,
    this.isDateCustom = false,
    this.isTimeCustom = false,
  });

  final String name;

  /// Whole RWF.
  final int amount;

  final PaymentMethod method;

  /// The moment set by hand, or `null` when both the date and the clock were
  /// left alone — in which case the expense is stamped as it is written.
  final DateTime? at;

  /// The expense was dated to an earlier day than today.
  final bool isDateCustom;

  /// The clock was moved off the current time.
  final bool isTimeCustom;
}

/// Records one expense: what it was, what it cost, when, and how it was paid.
///
/// Built as the payment sheet's twin on purpose. The same people use both, and
/// an expense is the same shape of fact as a sale with the money running the
/// other way: a large read-back of the amount, the two optional stamp rows
/// defaulting to now, and one big button per payment method — where choosing
/// the method *is* the confirmation, so there is no second confirm step to
/// learn.
class ExpenseFormSheet extends StatefulWidget {
  const ExpenseFormSheet({super.key, required this.methods});

  final List<PaymentMethod> methods;

  /// Shows the sheet and resolves to the expense to record, or `null` if
  /// dismissed.
  static Future<ExpenseDraft?> show(
    BuildContext context, {
    required List<PaymentMethod> methods,
  }) {
    return showModalBottomSheet<ExpenseDraft>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => ExpenseFormSheet(methods: methods),
    );
  }

  @override
  State<ExpenseFormSheet> createState() => _ExpenseFormSheetState();
}

class _ExpenseFormSheetState extends State<ExpenseFormSheet> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _amount = TextEditingController();

  /// The clock reading shown while nothing has been set by hand. It does not
  /// tick — an expense left on the clock is stamped by the repository at write
  /// time — but it is re-read whenever the stamp is handed back to the clock.
  DateTime _clockTime = DateTime.now();

  /// Held apart for the same reason the payment sheet holds them apart:
  /// backdating an expense and correcting its clock are separate corrections,
  /// and either can be undone without disturbing the other.
  DateTime? _customDate;
  DateTime? _customTime;

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    super.dispose();
  }

  DateTime get _effectiveDate => _customDate ?? startOfDay(_clockTime);

  /// What the expense will be stamped with if it is confirmed now.
  DateTime get _effectiveMoment {
    final clock = _customTime ?? _clockTime;
    return combineDateAndTime(_effectiveDate, clock.hour, clock.minute);
  }

  /// The stamp to hand the repository: `null` while both halves are still on
  /// the clock, so an expense entered as it happens is timed as it is written.
  DateTime? get _explicitStamp =>
      _customDate == null && _customTime == null ? null : _effectiveMoment;

  /// Whole RWF typed so far, or 0 while the field is empty or unparseable.
  int get _typedAmount => int.tryParse(_amount.text.trim()) ?? 0;

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
      title: 'Expense date',
      backdateNote:
          'This expense will be added to that day’s total, not today’s.',
    );
    if (picked == null || !mounted) return;

    // Landing back on today means nothing was really overridden.
    setState(() => _customDate = isSameDate(picked, today) ? null : picked);
  }

  Future<void> _editTime() async {
    final picked = await TimePadDialog.show(
      context,
      day: _effectiveDate,
      initial: TimeOfDay.fromDateTime(_effectiveMoment),
      title: 'Expense time',
    );
    if (picked == null || !mounted) return;

    // Landing on the current minute — usually via the pad's own "Now" — means
    // nothing was really overridden, so keep the clock half on the clock.
    if (formatHourMinute(picked) == formatHourMinute(DateTime.now())) {
      _useClock();
    } else {
      setState(() => _customTime = picked);
    }
  }

  /// Choosing the method confirms the expense, once the form is valid.
  void _submit(PaymentMethod method) {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    Navigator.of(context).pop(
      ExpenseDraft(
        name: _name.text.trim(),
        amount: int.parse(_amount.text.trim()),
        method: method,
        at: _explicitStamp,
        isDateCustom: _customDate != null,
        isTimeCustom: _customTime != null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return SafeArea(
      child: Padding(
        // The bottom inset keeps the payment buttons above the on-screen
        // keyboard, which the till's sheet never has to deal with.
        padding: EdgeInsets.fromLTRB(
          28,
          4,
          28,
          28 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'New expense',
                  style: TextStyle(fontSize: 17, color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 4),
                // The read-back, in the same place and size as the sale total:
                // separators make a stray zero visible before it is committed.
                Text(
                  formatRwfWithUnit(_typedAmount),
                  style: TextStyle(
                    fontSize: 42,
                    fontWeight: FontWeight.w800,
                    color: scheme.primary,
                  ),
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _name,
                  autofocus: true,
                  textCapitalization: TextCapitalization.sentences,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'What was it for?',
                    helperText: 'Milk, gas bottle, transport…',
                  ),
                  style: const TextStyle(fontSize: 18),
                  validator: (value) => (value == null || value.trim().isEmpty)
                      ? 'Give the expense a name.'
                      : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _amount,
                  decoration: const InputDecoration(
                    labelText: 'Amount (RWF)',
                    helperText: 'Whole francs, no decimals',
                  ),
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  // Keeps the big read-back above in step with the keypad.
                  onChanged: (_) => setState(() {}),
                  validator: (value) {
                    final parsed = int.tryParse((value ?? '').trim());
                    if (parsed == null) {
                      return 'Enter an amount in whole francs.';
                    }
                    if (parsed <= 0) return 'Enter an amount above zero.';
                    if (parsed > Expense.maxAmount) {
                      return 'That looks too large — check the figure.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 20),
                StampRow(
                  icon: Icons.event_outlined,
                  label: 'Expense date',
                  customLabel: 'Expense date (backdated)',
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
                  label: 'Expense time',
                  customLabel: 'Expense time (edited)',
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
                    'How was it paid?',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final method in widget.methods)
                      SizedBox(
                        width: 200,
                        height: 84,
                        child: FilledButton.tonal(
                          onPressed: () => _submit(method),
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
                    child: const Text('Cancel'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
