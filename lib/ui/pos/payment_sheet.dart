import 'package:flutter/material.dart';

import '../../core/money.dart';
import '../../data/models/payment_method.dart';
import '../theme.dart';

/// Payment step: pick a method and the sale is committed.
///
/// Choosing the method *is* the confirmation — there is no second "confirm"
/// button. That keeps a one-item sale at three taps (product → Charge →
/// method) while leaving the amount large and legible for the read-back.
class PaymentSheet extends StatelessWidget {
  const PaymentSheet({
    super.key,
    required this.total,
    required this.itemCount,
    required this.methods,
  });

  final int total;
  final int itemCount;
  final List<PaymentMethod> methods;

  /// Shows the sheet and resolves to the chosen method, or `null` if dismissed.
  static Future<PaymentMethod?> show(
    BuildContext context, {
    required int total,
    required int itemCount,
    required List<PaymentMethod> methods,
  }) {
    return showModalBottomSheet<PaymentMethod>(
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
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 4, 28, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$itemCount item${itemCount == 1 ? '' : 's'}',
              style: TextStyle(fontSize: 17, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 4),
            Text(
              formatRwfWithUnit(total),
              style: TextStyle(
                fontSize: 42,
                fontWeight: FontWeight.w800,
                color: scheme.primary,
              ),
            ),
            const SizedBox(height: 22),
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
                for (final method in methods)
                  SizedBox(
                    width: 200,
                    height: 84,
                    child: FilledButton.tonal(
                      onPressed: () => Navigator.of(context).pop(method),
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
