import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_date.dart';
import '../../core/app_exception.dart';
import '../../core/money.dart';
import '../../data/models/expense.dart';
import '../../repositories/expense_repository.dart';
import '../../repositories/payment_method_repository.dart';
import '../widgets/async_value_view.dart';
import 'expense_form_sheet.dart';
import 'order_views.dart';

/// Records what the shop spent, day by day.
///
/// The back-office counterpart of the till: the same day picker as Order
/// history above a list of what went out, and an Add expense button that opens
/// a form built to read like the payment sheet staff already use.
///
/// Like an order, an expense is voided rather than deleted — it keeps its row,
/// gains a reason and a timestamp, and stays in the Excel export marked
/// `voided` while dropping out of the day's total.
class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key});

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  DateTime _date = startOfDay(DateTime.now());
  List<Expense> _expenses = const [];
  ExpenseDayTotals? _totals;
  bool _loading = true;
  bool _saving = false;
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
      final repository = context.read<ExpenseRepository>();
      final expenses = await repository.expensesForDate(_date);
      final totals = await repository.totalsForDate(_date);

      if (!mounted) return;
      setState(() {
        // Newest first: the expense most likely to need correcting is the one
        // just entered.
        _expenses = expenses.reversed.toList(growable: false);
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

  Future<void> _add() async {
    try {
      final methods =
          await context.read<PaymentMethodRepository>().activeMethods();
      if (!mounted) return;

      if (methods.isEmpty) {
        showAppSnackBar(
          context,
          'Add a payment method first — an expense has to be paid out of '
          'something.',
          isError: true,
        );
        return;
      }

      final draft = await ExpenseFormSheet.show(context, methods: methods);
      if (draft == null || !mounted) return;

      setState(() => _saving = true);

      final expense = await context.read<ExpenseRepository>().createExpense(
            name: draft.name,
            amount: draft.amount,
            paymentMethod: draft.method,
            // Null unless the date or the time was set by hand, which leaves
            // the repository to stamp the expense as it writes it.
            now: draft.at,
          );

      if (!mounted) return;

      // Read a hand-set stamp back, so a mistyped one is caught now rather
      // than at month end. A backdated expense names its day, since that is
      // the part that moves it out of the total on screen.
      final stamp = [
        if (draft.isDateCustom)
          formatRelativeDate(
            parseIsoDate(expense.businessDate) ?? expense.createdAt,
            today: startOfDay(DateTime.now()),
          ),
        if (draft.isTimeCustom) expense.timeLabel,
      ].join(' at ');

      showAppSnackBar(
        context,
        stamp.isEmpty
            ? 'Recorded ${expense.name} · ${formatRwfWithUnit(expense.amount)}.'
            : 'Recorded ${expense.name} · '
                '${formatRwfWithUnit(expense.amount)} ($stamp).',
      );

      // A backdated expense belongs to another day; jump there so it is
      // visible rather than apparently missing.
      final recordedDay = parseIsoDate(expense.businessDate);
      if (recordedDay != null && !isSameDate(recordedDay, _date)) {
        setState(() => _date = recordedDay);
      }
      await _load();
    } on AppException catch (error) {
      if (!mounted) return;
      showAppSnackBar(context, error.message, isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _void(Expense expense) async {
    final id = expense.id;
    if (id == null) return;

    final reason = await showDialog<String>(
      context: context,
      builder: (_) => _VoidExpenseDialog(expense: expense),
    );
    if (reason == null || !mounted) return;

    try {
      await context
          .read<ExpenseRepository>()
          .voidExpense(expenseId: id, reason: reason);
      if (!mounted) return;
      showAppSnackBar(context, '"${expense.name}" voided.');
      await _load();
    } on AppException catch (error) {
      if (!mounted) return;
      showAppSnackBar(context, error.message, isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Expenses'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: FilledButton.icon(
              onPressed: _saving ? null : _add,
              icon: const Icon(Icons.add),
              label: const Text('Add expense'),
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
                    : _expenses.isEmpty
                        ? EmptyView(
                            icon: Icons.receipt_outlined,
                            message: 'Nothing recorded on this day.',
                            action: FilledButton.icon(
                              onPressed: _saving ? null : _add,
                              icon: const Icon(Icons.add),
                              label: const Text('Add the first expense'),
                            ),
                          )
                        : Column(
                            children: [
                              if (_totals != null) _DayCard(totals: _totals!),
                              const Divider(height: 1),
                              Expanded(
                                child: ListView.separated(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 8),
                                  itemCount: _expenses.length,
                                  separatorBuilder: (_, __) =>
                                      const Divider(height: 1),
                                  itemBuilder: (context, index) => _ExpenseTile(
                                    expense: _expenses[index],
                                    onVoid: () => _void(_expenses[index]),
                                  ),
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

/// What the day cost, above the list.
class _DayCard extends StatelessWidget {
  const _DayCard({required this.totals});

  final ExpenseDayTotals totals;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      color: scheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Spent this day',
                style: TextStyle(fontSize: 15, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 2),
              Text(
                formatRwfWithUnit(totals.spend),
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: scheme.primary,
                ),
              ),
            ],
          ),
          const Spacer(),
          Text(
            [
              '${totals.expenseCount} '
                  'expense${totals.expenseCount == 1 ? '' : 's'}',
              if (totals.voidedCount > 0) '${totals.voidedCount} voided',
            ].join(' · '),
            style: TextStyle(fontSize: 16, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// One recorded expense, expanding to its void controls or its void reason.
class _ExpenseTile extends StatelessWidget {
  const _ExpenseTile({required this.expense, required this.onVoid});

  final Expense expense;
  final VoidCallback onVoid;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return ExpansionTile(
      tilePadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      childrenPadding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
      title: Row(
        children: [
          Expanded(
            child: Text(
              expense.name,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                decoration:
                    expense.isVoided ? TextDecoration.lineThrough : null,
                color: expense.isVoided ? scheme.outline : scheme.onSurface,
              ),
            ),
          ),
          if (expense.isVoided) ...[
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: scheme.errorContainer,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'VOIDED',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: scheme.onErrorContainer,
                ),
              ),
            ),
          ],
          const SizedBox(width: 12),
          Text(
            formatRwfWithUnit(expense.amount),
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: expense.isVoided ? scheme.outline : scheme.onSurface,
            ),
          ),
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          '${expense.timeLabel} · ${expense.paymentMethodName}',
          style: TextStyle(fontSize: 15, color: scheme.onSurfaceVariant),
        ),
      ),
      children: [
        if (expense.isVoided)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: scheme.errorContainer.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Void reason',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: scheme.onErrorContainer,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  expense.voidReason ?? '—',
                  style: const TextStyle(fontSize: 16),
                ),
                if (expense.voidedAt != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Voided ${formatIsoDate(expense.voidedAt!)} at '
                    '${formatHourMinute(expense.voidedAt!)}',
                    style: TextStyle(
                      fontSize: 14,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          )
        else
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              onPressed: onVoid,
              icon: const Icon(Icons.block),
              label: const Text('Void this expense'),
              style: OutlinedButton.styleFrom(foregroundColor: scheme.error),
            ),
          ),
      ],
    );
  }
}

/// Collects the mandatory void reason, as the order version does.
class _VoidExpenseDialog extends StatefulWidget {
  const _VoidExpenseDialog({required this.expense});

  final Expense expense;

  @override
  State<_VoidExpenseDialog> createState() => _VoidExpenseDialogState();
}

class _VoidExpenseDialogState extends State<_VoidExpenseDialog> {
  final _formKey = GlobalKey<FormState>();
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Void "${widget.expense.name}"?'),
      content: SizedBox(
        width: 480,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'The expense stays in the records and in the Excel export, '
                'marked as voided. It stops counting toward the day total.',
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 18),
              TextFormField(
                controller: _reason,
                autofocus: true,
                maxLength: 200,
                minLines: 2,
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Reason',
                  helperText: 'Appears in the Notes column of the export',
                ),
                style: const TextStyle(fontSize: 17),
                validator: (value) => (value == null || value.trim().isEmpty)
                    ? 'A reason is required.'
                    : null,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (_formKey.currentState?.validate() ?? false) {
              Navigator.of(context).pop(_reason.text.trim());
            }
          },
          child: const Text('Void expense'),
        ),
      ],
    );
  }
}
