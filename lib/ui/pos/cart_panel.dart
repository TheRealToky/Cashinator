import 'package:flutter/material.dart';

import '../../core/money.dart';
import '../../state/cart_controller.dart';
import '../theme.dart';
import '../widgets/async_value_view.dart';

/// The running sale, pinned to the right of the product grid in landscape.
///
/// Each line has its own −/+ controls so a mis-tap is corrected in place,
/// without opening a dialog or clearing the cart.
class CartPanel extends StatelessWidget {
  const CartPanel({
    super.key,
    required this.cart,
    required this.onCheckout,
    required this.onClear,
    required this.busy,
  });

  final CartController cart;
  final VoidCallback onCheckout;
  final VoidCallback onClear;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: AppTheme.cartPanelWidth,
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(left: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Column(
        children: [
          _CartHeader(cart: cart, onClear: cart.isEmpty ? null : onClear),
          const Divider(height: 1),
          Expanded(
            child: cart.isEmpty
                ? const EmptyView(
                    icon: Icons.shopping_basket_outlined,
                    message: 'Tap a product to start a sale.',
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: cart.items.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final item = cart.items[index];
                      return _CartLineTile(
                        item: item,
                        onIncrement: () => cart.add(item.product),
                        onDecrement: () => cart.decrement(item.product),
                        onRemove: () => cart.removeLine(item.product),
                      );
                    },
                  ),
          ),
          const Divider(height: 1),
          _CartFooter(
            cart: cart,
            busy: busy,
            onCheckout: cart.isEmpty || busy ? null : onCheckout,
          ),
        ],
      ),
    );
  }
}

class _CartHeader extends StatelessWidget {
  const _CartHeader({required this.cart, this.onClear});

  final CartController cart;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Current sale',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  cart.isEmpty
                      ? 'No items yet'
                      : '${cart.itemCount} item${cart.itemCount == 1 ? '' : 's'}',
                  style: TextStyle(
                    fontSize: 15,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onClear,
            icon: const Icon(Icons.delete_outline),
            iconSize: 26,
            tooltip: 'Clear the cart',
            style: IconButton.styleFrom(
              minimumSize: const Size(
                AppTheme.minTapTarget,
                AppTheme.minTapTarget,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CartLineTile extends StatelessWidget {
  const _CartLineTile({
    required this.item,
    required this.onIncrement,
    required this.onDecrement,
    required this.onRemove,
  });

  final CartItem item;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 10, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  item.product.name,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                formatRwf(item.lineTotal),
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text(
                '${formatRwf(item.product.price)} each',
                style: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant),
              ),
              const Spacer(),
              _QtyButton(
                icon: item.qty == 1
                    ? Icons.delete_outline
                    : Icons.remove,
                onPressed: item.qty == 1 ? onRemove : onDecrement,
                tooltip: item.qty == 1 ? 'Remove line' : 'One less',
              ),
              SizedBox(
                width: 44,
                child: Text(
                  '${item.qty}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              _QtyButton(
                icon: Icons.add,
                onPressed: onIncrement,
                tooltip: 'One more',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _QtyButton extends StatelessWidget {
  const _QtyButton({
    required this.icon,
    required this.onPressed,
    required this.tooltip,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: AppTheme.minTapTarget,
        height: AppTheme.minTapTarget,
        child: OutlinedButton(
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
            padding: EdgeInsets.zero,
            minimumSize: const Size(
              AppTheme.minTapTarget,
              AppTheme.minTapTarget,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          child: Icon(icon, size: 22),
        ),
      ),
    );
  }
}

class _CartFooter extends StatelessWidget {
  const _CartFooter({
    required this.cart,
    required this.onCheckout,
    required this.busy,
  });

  final CartController cart;
  final VoidCallback? onCheckout;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Total',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 12),
              // The total must never be clipped — it is the number the customer
              // is told to pay. A six-figure basket ("135 000 RWF") is wider
              // than this panel at 26pt, so let it shrink rather than overflow.
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    formatRwfWithUnit(cart.total),
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: scheme.primary,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 64,
            child: FilledButton.icon(
              onPressed: onCheckout,
              icon: busy
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.payments_outlined, size: 26),
              label: Text(busy ? 'Saving…' : 'Charge'),
            ),
          ),
        ],
      ),
    );
  }
}
