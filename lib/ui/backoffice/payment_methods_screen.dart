import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_exception.dart';
import '../../data/models/payment_method.dart';
import '../../repositories/payment_method_repository.dart';
import '../../state/catalog_controller.dart';
import '../widgets/async_value_view.dart';

/// Payment method CRUD.
class PaymentMethodsScreen extends StatefulWidget {
  const PaymentMethodsScreen({super.key});

  @override
  State<PaymentMethodsScreen> createState() => _PaymentMethodsScreenState();
}

class _PaymentMethodsScreenState extends State<PaymentMethodsScreen> {
  List<PaymentMethod> _methods = const [];
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
      final methods =
          await context.read<PaymentMethodRepository>().allMethods();
      if (!mounted) return;
      setState(() {
        _methods = methods;
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

  Future<void> _refreshEverything() async {
    await _load();
    if (mounted) await context.read<CatalogController>().refresh();
  }

  Future<void> _edit(PaymentMethod? existing) async {
    final saved = await showDialog<PaymentMethod>(
      context: context,
      builder: (_) => _PaymentMethodFormDialog(method: existing),
    );
    if (saved == null || !mounted) return;

    try {
      final repository = context.read<PaymentMethodRepository>();
      if (saved.id == null) {
        await repository.create(saved);
      } else {
        await repository.update(saved);
      }
      if (!mounted) return;
      showAppSnackBar(context, 'Saved "${saved.name}".');
      await _refreshEverything();
    } on AppException catch (error) {
      if (!mounted) return;
      showAppSnackBar(context, error.message, isError: true);
    }
  }

  Future<void> _toggleActive(PaymentMethod method) async {
    final id = method.id;
    if (id == null) return;

    try {
      await context
          .read<PaymentMethodRepository>()
          .setActive(id, active: !method.active);
      if (!mounted) return;
      await _refreshEverything();
    } on AppException catch (error) {
      if (!mounted) return;
      showAppSnackBar(context, error.message, isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Payment methods'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: FilledButton.icon(
              onPressed: () => _edit(null),
              icon: const Icon(Icons.add),
              label: const Text('New method'),
            ),
          ),
        ],
      ),
      body: _loading
          ? const LoadingView()
          : _error != null
              ? ErrorView(message: _error!, onRetry: _load)
              : Column(
                  children: [
                    const _ExportNotice(),
                    Expanded(
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: _methods.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final method = _methods[index];
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 10,
                            ),
                            onTap: () => _edit(method),
                            title: Text(
                              method.name,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: method.active
                                ? null
                                : const Padding(
                                    padding: EdgeInsets.only(top: 4),
                                    child: Text('Not offered at the till'),
                                  ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Switch(
                                  value: method.active,
                                  onChanged: (_) => _toggleActive(method),
                                ),
                                const SizedBox(width: 8),
                                IconButton(
                                  onPressed: () => _edit(method),
                                  icon: const Icon(Icons.edit_outlined),
                                  iconSize: 26,
                                  tooltip: 'Edit',
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
    );
  }
}

/// Explains the one non-obvious consequence of adding a method.
class _ExportNotice extends StatelessWidget {
  const _ExportNotice();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(24, 16, 24, 8),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: scheme.primary, size: 26),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              'Each method used in a period gets its own column in the Excel '
              'Day Summary sheet. Cash, MoMo and Card always appear; anything '
              'else is added after them.',
              style: TextStyle(fontSize: 15, color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

class _PaymentMethodFormDialog extends StatefulWidget {
  const _PaymentMethodFormDialog({this.method});

  final PaymentMethod? method;

  @override
  State<_PaymentMethodFormDialog> createState() =>
      _PaymentMethodFormDialogState();
}

class _PaymentMethodFormDialogState extends State<_PaymentMethodFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late bool _active;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.method?.name ?? '');
    _active = widget.method?.active ?? true;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    Navigator.of(context).pop(
      PaymentMethod(
        id: widget.method?.id,
        name: _name.text.trim(),
        active: _active,
        sortOrder: widget.method?.sortOrder ?? 0,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.method == null ? 'New payment method' : 'Edit method'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _name,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Name'),
                style: const TextStyle(fontSize: 18),
                validator: (value) => (value == null || value.trim().isEmpty)
                    ? 'Enter a name.'
                    : null,
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                value: _active,
                onChanged: (value) => setState(() => _active = value),
                title: const Text('Offered at the till'),
                contentPadding: EdgeInsets.zero,
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
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}
