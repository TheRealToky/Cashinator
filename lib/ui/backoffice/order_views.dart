/// Widgets shared by the back-office screens that list a day's orders:
/// Order history and Sample.
///
/// They differ only in which orders they load and whether voiding is offered,
/// so the day picker and the order row live here rather than being copied.
library;

import 'package:flutter/material.dart';

import '../../core/app_date.dart';
import '../../core/money.dart';
import '../../repositories/order_repository.dart';

/// Day picker with previous/next arrows, sitting above an order list.
///
/// [onNext] is null on the newest day the screen allows, which greys the arrow
/// out rather than hiding it — the bar keeps its shape as the day changes.
class OrderDateBar extends StatelessWidget {
  const OrderDateBar({
    super.key,
    required this.date,
    required this.onPrevious,
    required this.onNext,
    required this.onPick,
  });

  final DateTime date;
  final VoidCallback onPrevious;
  final VoidCallback? onNext;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            onPressed: onPrevious,
            icon: const Icon(Icons.chevron_left),
            iconSize: 32,
            tooltip: 'Previous day',
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: onPick,
            icon: const Icon(Icons.calendar_today_outlined),
            label: Text(formatIsoDate(date)),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: onNext,
            icon: const Icon(Icons.chevron_right),
            iconSize: 32,
            tooltip: 'Next day',
          ),
        ],
      ),
    );
  }
}

/// One order, expanding to its lines.
///
/// Leave [onVoid] null for a read-only listing: the void button disappears and
/// the tile shows the sale exactly as recorded.
class OrderTile extends StatelessWidget {
  const OrderTile({super.key, required this.entry, this.onVoid});

  final OrderWithLines entry;
  final VoidCallback? onVoid;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final order = entry.order;

    return ExpansionTile(
      tilePadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      childrenPadding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
      title: Row(
        children: [
          Text(
            'Order ${order.orderLabel}',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              decoration: order.isVoided ? TextDecoration.lineThrough : null,
              color: order.isVoided ? scheme.outline : scheme.onSurface,
            ),
          ),
          const SizedBox(width: 12),
          if (order.isVoided)
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
          const Spacer(),
          Text(
            formatRwfWithUnit(order.total),
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: order.isVoided ? scheme.outline : scheme.onSurface,
            ),
          ),
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          '${order.timeLabel} · ${order.paymentMethodName} · '
          '${entry.itemCount} item${entry.itemCount == 1 ? '' : 's'}',
          style: TextStyle(fontSize: 15, color: scheme.onSurfaceVariant),
        ),
      ),
      children: [
        for (final line in entry.lines)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                SizedBox(
                  width: 48,
                  child: Text(
                    '${line.qty}×',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    line.productName,
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
                Text(
                  formatRwf(line.lineTotal),
                  style: const TextStyle(fontSize: 16),
                ),
              ],
            ),
          ),
        if (order.isVoided) ...[
          const SizedBox(height: 12),
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
                  order.voidReason ?? '—',
                  style: const TextStyle(fontSize: 16),
                ),
                if (order.voidedAt != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Voided ${formatIsoDate(order.voidedAt!)} at '
                    '${formatHourMinute(order.voidedAt!)}',
                    style: TextStyle(
                      fontSize: 14,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ] else if (onVoid != null) ...[
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              onPressed: onVoid,
              icon: const Icon(Icons.block),
              label: const Text('Void this order'),
              style: OutlinedButton.styleFrom(
                foregroundColor: scheme.error,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
