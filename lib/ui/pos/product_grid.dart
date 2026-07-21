import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/money.dart';
import '../../data/models/product.dart';
import '../theme.dart';

/// The tappable product catalogue.
///
/// Tiles are large and text-only — the shop has no product photography, and
/// words are faster to scan than icons for a catalogue this size.
class ProductGrid extends StatelessWidget {
  const ProductGrid({
    super.key,
    required this.products,
    required this.onTap,
    required this.qtyOf,
  });

  final List<Product> products;
  final ValueChanged<Product> onTap;

  /// Current cart quantity for a product, shown as a badge on the tile.
  final int Function(Product) qtyOf;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Aim for ~200dp-wide tiles, so the 11" tablet lands on 4–5 columns in
        // landscape and stays usable if the window is ever narrower.
        final columns = (constraints.maxWidth / 200).floor().clamp(2, 6);

        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          // Virtualised by default — the catalogue is small today, but a long
          // list must not build every tile up front.
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisExtent: AppTheme.productTileHeight,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemCount: products.length,
          itemBuilder: (context, index) {
            final product = products[index];
            return _ProductTile(
              product: product,
              qtyInCart: qtyOf(product),
              onTap: () {
                HapticFeedback.selectionClick();
                onTap(product);
              },
            );
          },
        );
      },
    );
  }
}

class _ProductTile extends StatelessWidget {
  const _ProductTile({
    required this.product,
    required this.qtyInCart,
    required this.onTap,
  });

  final Product product;
  final int qtyInCart;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final inCart = qtyInCart > 0;

    return Material(
      color: inCart ? scheme.primaryContainer : scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    product.name,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 17,
                      height: 1.2,
                      fontWeight: FontWeight.w600,
                      color: inCart
                          ? scheme.onPrimaryContainer
                          : scheme.onSurface,
                    ),
                  ),
                  Text(
                    formatRwf(product.price),
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                      color: inCart
                          ? scheme.onPrimaryContainer
                          : scheme.primary,
                    ),
                  ),
                ],
              ),
            ),
            if (inCart)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '$qtyInCart',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: scheme.onPrimary,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Horizontal category filter above the grid.
class CategoryFilterBar extends StatelessWidget {
  const CategoryFilterBar({
    super.key,
    required this.categories,
    required this.selected,
    required this.onSelected,
  });

  final List<String> categories;
  final String? selected;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    if (categories.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 64,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          _FilterChipButton(
            label: 'All',
            selected: selected == null,
            onTap: () => onSelected(null),
          ),
          for (final category in categories)
            _FilterChipButton(
              label: category,
              selected: selected == category,
              onTap: () => onSelected(category),
            ),
        ],
      ),
    );
  }
}

class _FilterChipButton extends StatelessWidget {
  const _FilterChipButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 10, top: 8, bottom: 8),
      child: ChoiceChip(
        label: Text(label, style: const TextStyle(fontSize: 16)),
        selected: selected,
        onSelected: (_) => onTap(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    );
  }
}
