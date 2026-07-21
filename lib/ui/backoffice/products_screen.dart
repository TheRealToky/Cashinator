import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/app_exception.dart';
import '../../core/money.dart';
import '../../data/models/product.dart';
import '../../repositories/product_repository.dart';
import '../../state/catalog_controller.dart';
import '../widgets/async_value_view.dart';

/// Product CRUD. Deactivation replaces deletion throughout.
class ProductsScreen extends StatefulWidget {
  const ProductsScreen({super.key});

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  List<Product> _products = const [];
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
      final products = await context.read<ProductRepository>().allProducts();
      if (!mounted) return;
      setState(() {
        _products = products;
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

  /// Keeps the till in sync after any catalogue change.
  Future<void> _refreshEverything() async {
    await _load();
    if (mounted) await context.read<CatalogController>().refresh();
  }

  Future<void> _edit(Product? existing) async {
    final saved = await showDialog<Product>(
      context: context,
      builder: (_) => _ProductFormDialog(product: existing),
    );
    if (saved == null || !mounted) return;

    try {
      final repository = context.read<ProductRepository>();
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

  Future<void> _toggleActive(Product product) async {
    final id = product.id;
    if (id == null) return;

    try {
      await context
          .read<ProductRepository>()
          .setActive(id, active: !product.active);
      if (!mounted) return;
      showAppSnackBar(
        context,
        product.active
            ? '"${product.name}" is hidden from the till.'
            : '"${product.name}" is back on the till.',
      );
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
        title: const Text('Products'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: FilledButton.icon(
              onPressed: () => _edit(null),
              icon: const Icon(Icons.add),
              label: const Text('New product'),
            ),
          ),
        ],
      ),
      body: _loading
          ? const LoadingView()
          : _error != null
              ? ErrorView(message: _error!, onRetry: _load)
              : _products.isEmpty
                  ? EmptyView(
                      icon: Icons.bakery_dining_outlined,
                      message: 'No products yet.',
                      action: FilledButton.icon(
                        onPressed: () => _edit(null),
                        icon: const Icon(Icons.add),
                        label: const Text('Add the first product'),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: _products.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final product = _products[index];
                        return _ProductRow(
                          product: product,
                          onEdit: () => _edit(product),
                          onToggleActive: () => _toggleActive(product),
                        );
                      },
                    ),
    );
  }
}

class _ProductRow extends StatelessWidget {
  const _ProductRow({
    required this.product,
    required this.onEdit,
    required this.onToggleActive,
  });

  final Product product;
  final VoidCallback onEdit;
  final VoidCallback onToggleActive;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      onTap: onEdit,
      title: Text(
        product.name,
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          // Deactivated rows stay legible but visibly out of service.
          color: product.active ? scheme.onSurface : scheme.outline,
        ),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          [
            formatRwfWithUnit(product.price),
            if (product.category != null && product.category!.isNotEmpty)
              product.category!,
            if (!product.active) 'Hidden from the till',
          ].join(' · '),
          style: TextStyle(fontSize: 15, color: scheme.onSurfaceVariant),
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Switch(
            value: product.active,
            onChanged: (_) => onToggleActive(),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: onEdit,
            icon: const Icon(Icons.edit_outlined),
            iconSize: 26,
            tooltip: 'Edit',
          ),
        ],
      ),
    );
  }
}

/// Add/edit form. Returns the edited [Product], or `null` when cancelled.
class _ProductFormDialog extends StatefulWidget {
  const _ProductFormDialog({this.product});

  final Product? product;

  @override
  State<_ProductFormDialog> createState() => _ProductFormDialogState();
}

class _ProductFormDialogState extends State<_ProductFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _price;
  late final TextEditingController _category;
  late bool _active;

  @override
  void initState() {
    super.initState();
    final product = widget.product;
    _name = TextEditingController(text: product?.name ?? '');
    _price = TextEditingController(
      text: product == null ? '' : product.price.toString(),
    );
    _category = TextEditingController(text: product?.category ?? '');
    _active = product?.active ?? true;
  }

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    _category.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final category = _category.text.trim();
    final result = Product(
      id: widget.product?.id,
      name: _name.text.trim(),
      price: int.parse(_price.text.trim()),
      category: category.isEmpty ? null : category,
      active: _active,
      sortOrder: widget.product?.sortOrder ?? 0,
    );

    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.product == null;

    return AlertDialog(
      title: Text(isNew ? 'New product' : 'Edit product'),
      content: SizedBox(
        width: 460,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _name,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Name'),
                style: const TextStyle(fontSize: 18),
                validator: (value) => (value == null || value.trim().isEmpty)
                    ? 'Enter a name.'
                    : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _price,
                decoration: const InputDecoration(
                  labelText: 'Price (RWF)',
                  helperText: 'Whole francs, no decimals',
                ),
                style: const TextStyle(fontSize: 18),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                validator: (value) {
                  final parsed = int.tryParse((value ?? '').trim());
                  if (parsed == null) return 'Enter a price in whole francs.';
                  if (parsed < 0) return 'Price cannot be negative.';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _category,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Category (optional)',
                  helperText: 'Groups the product on the till',
                ),
                style: const TextStyle(fontSize: 18),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                value: _active,
                onChanged: (value) => setState(() => _active = value),
                title: const Text('Shown on the till'),
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
