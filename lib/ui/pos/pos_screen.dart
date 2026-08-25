import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/app_date.dart';
import '../../core/app_exception.dart';
import '../../core/money.dart';
import '../../repositories/order_repository.dart';
import '../../state/cart_controller.dart';
import '../../state/catalog_controller.dart';
import '../widgets/async_value_view.dart';
import 'cart_panel.dart';
import 'payment_sheet.dart';
import 'product_grid.dart';

/// The till. Product grid on the left, live cart on the right.
///
/// This screen is where staff spend the whole day, so it never navigates away
/// during a sale: the payment step is a sheet, and confirmation is a snack bar.
class PosScreen extends StatefulWidget {
  const PosScreen({super.key});

  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen> {
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // Deferred to the first frame so the loading state has somewhere to render.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<CatalogController>().load();
    });
  }

  Future<void> _checkout() async {
    final cart = context.read<CartController>();
    final catalog = context.read<CatalogController>();

    if (cart.isEmpty || _saving) return;

    if (catalog.activeMethods.isEmpty) {
      showAppSnackBar(
        context,
        'No payment methods are set up. Ask management to add one.',
        isError: true,
      );
      return;
    }

    final choice = await PaymentSheet.show(
      context,
      total: cart.total,
      itemCount: cart.itemCount,
      methods: catalog.activeMethods,
    );
    if (choice == null || !mounted) return;

    setState(() => _saving = true);

    try {
      final order = await context.read<OrderRepository>().createOrder(
            lines: cart.toDraftLines(),
            paymentMethod: choice.method,
            // Null unless the cashier set the date or the time by hand, which
            // leaves the repository to stamp the sale as it writes it.
            now: choice.at,
          );

      if (!mounted) return;

      final total = cart.total;
      // Only clear once the write succeeded — a failed save must leave the cart
      // exactly as it was so the cashier can retry without re-ringing it.
      cart.clear();
      unawaited(HapticFeedback.mediumImpact());

      // Read any hand-set stamp back, so a mistyped one is caught now rather
      // than at the end of the day. A backdated sale names its day, since that
      // is the part that moves the sale out of the totals on screen.
      final stamp = [
        if (choice.isDateCustom)
          'on ${formatRelativeDate(order.createdAt, today: DateTime.now())}',
        if (choice.isTimeCustom) 'at ${order.timeLabel}',
      ].join(' ');

      showAppSnackBar(
        context,
        'Order ${order.orderLabel} recorded · '
        '${formatRwfWithUnit(total)} · ${choice.method.name}'
        '${stamp.isEmpty ? '' : ' · $stamp'}',
      );
    } on AppException catch (error) {
      if (!mounted) return;
      showAppSnackBar(context, error.message, isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _confirmClear() async {
    final cart = context.read<CartController>();
    if (cart.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear this sale?'),
        content: Text(
          'The ${cart.itemCount} item${cart.itemCount == 1 ? '' : 's'} in the '
          'cart will be removed. Nothing has been recorded yet.',
          style: const TextStyle(fontSize: 17),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep it'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      cart.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final catalog = context.watch<CatalogController>();
    final cart = context.watch<CartController>();

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Till'),
        actions: [
          IconButton(
            onPressed: () => catalog.refresh(),
            icon: const Icon(Icons.refresh),
            iconSize: 26,
            tooltip: 'Reload products',
          ),
          const SizedBox(width: 4),
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: OutlinedButton.icon(
              onPressed: () => _signOut(context, cart),
              icon: const Icon(Icons.lock_outline),
              label: const Text('Sign out'),
            ),
          ),
        ],
      ),
      body: switch (catalog.state) {
        LoadState.idle || LoadState.loading =>
          const LoadingView(label: 'Loading products…'),
        LoadState.failed => ErrorView(
            message: catalog.errorMessage ?? 'Something went wrong.',
            onRetry: catalog.refresh,
          ),
        LoadState.ready => _buildTill(context, catalog, cart),
      },
    );
  }

  Widget _buildTill(
    BuildContext context,
    CatalogController catalog,
    CartController cart,
  ) {
    if (catalog.activeProducts.isEmpty) {
      return const EmptyView(
        icon: Icons.storefront_outlined,
        message: 'No active products yet.\n'
            'Ask management to add products in the back office.',
      );
    }

    final visible = catalog.visibleProducts;

    return Row(
      children: [
        Expanded(
          child: Column(
            children: [
              CategoryFilterBar(
                categories: catalog.categories,
                selected: catalog.selectedCategory,
                onSelected: catalog.selectCategory,
              ),
              Expanded(
                child: visible.isEmpty
                    ? const EmptyView(
                        icon: Icons.filter_alt_off_outlined,
                        message: 'Nothing in this category.',
                      )
                    : ProductGrid(
                        products: visible,
                        onTap: cart.add,
                        qtyOf: cart.qtyOf,
                      ),
              ),
            ],
          ),
        ),
        CartPanel(
          cart: cart,
          busy: _saving,
          onCheckout: _checkout,
          onClear: _confirmClear,
        ),
      ],
    );
  }

  Future<void> _signOut(BuildContext context, CartController cart) async {
    if (cart.isNotEmpty) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Sign out with an unfinished sale?'),
          content: const Text(
            'The current cart will be discarded. Nothing has been recorded '
            'yet.',
            style: TextStyle(fontSize: 17),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Stay'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Sign out'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    if (!context.mounted) return;
    cart.clear();
    Navigator.of(context).pop();
  }
}
