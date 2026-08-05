import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_date.dart';
import '../../core/app_exception.dart';
import '../../repositories/order_repository.dart';
import '../widgets/async_value_view.dart';
import 'order_views.dart';

/// Browse a day's orders and void them with a reason.
///
/// Voiding never removes anything: the order keeps its lines, gains a reason
/// and a timestamp, and still appears in the Excel `Sales Lines` sheet.
class OrderHistoryScreen extends StatefulWidget {
  const OrderHistoryScreen({super.key});

  @override
  State<OrderHistoryScreen> createState() => _OrderHistoryScreenState();
}

class _OrderHistoryScreenState extends State<OrderHistoryScreen> {
  DateTime _date = startOfDay(DateTime.now());
  List<OrderWithLines> _orders = const [];
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
      final orders =
          await context.read<OrderRepository>().ordersForDate(_date);
      if (!mounted) return;
      setState(() {
        // Newest first: the order most likely to need voiding is the last one.
        _orders = orders.reversed.toList(growable: false);
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

  Future<void> _void(OrderWithLines entry) async {
    final orderId = entry.order.id;
    if (orderId == null) return;

    final reason = await showDialog<String>(
      context: context,
      builder: (_) => _VoidReasonDialog(orderLabel: entry.order.orderLabel),
    );
    if (reason == null || !mounted) return;

    try {
      await context
          .read<OrderRepository>()
          .voidOrder(orderId: orderId, reason: reason);
      if (!mounted) return;
      showAppSnackBar(context, 'Order ${entry.order.orderLabel} voided.');
      await _load();
    } on AppException catch (error) {
      if (!mounted) return;
      showAppSnackBar(context, error.message, isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Order history')),
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
                    : _orders.isEmpty
                        ? const EmptyView(
                            icon: Icons.receipt_long_outlined,
                            message: 'No orders on this day.',
                          )
                        // Virtualised: a busy month browsed day by day stays
                        // light, and this is the only long list in the app.
                        : ListView.separated(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            itemCount: _orders.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) => OrderTile(
                              entry: _orders[index],
                              onVoid: () => _void(_orders[index]),
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}

/// Collects the mandatory void reason.
class _VoidReasonDialog extends StatefulWidget {
  const _VoidReasonDialog({required this.orderLabel});

  final String orderLabel;

  @override
  State<_VoidReasonDialog> createState() => _VoidReasonDialogState();
}

class _VoidReasonDialogState extends State<_VoidReasonDialog> {
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
      title: Text('Void order ${widget.orderLabel}?'),
      content: SizedBox(
        width: 480,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'The order stays in the records and in the Excel export, '
                'marked as voided. It stops counting toward sales totals.',
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
          child: const Text('Void order'),
        ),
      ],
    );
  }
}
