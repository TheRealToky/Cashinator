import 'package:flutter/material.dart';

import '../theme.dart';

/// One half of the stamp a record will be written with, and the way to change
/// it.
///
/// An overridden half is tinted, renamed and grows a reset button, so a
/// mistyped time or a record left pointing at last Tuesday is visible for the
/// whole entry step rather than only in the history later.
///
/// Shared by the till's payment sheet and the back office's expense form: the
/// two ask for the same two things — which day, which minute — and a cashier
/// who has learnt one has learnt the other.
class StampRow extends StatelessWidget {
  const StampRow({
    super.key,
    required this.icon,
    required this.label,
    required this.customLabel,
    required this.value,
    required this.isCustom,
    required this.onEdit,
    required this.onReset,
    required this.resetTooltip,
  });

  final IconData icon;
  final String label;
  final String customLabel;
  final String value;
  final bool isCustom;
  final VoidCallback onEdit;
  final VoidCallback onReset;
  final String resetTooltip;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: AppTheme.minTapTarget,
            child: OutlinedButton(
              onPressed: onEdit,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                alignment: Alignment.centerLeft,
                backgroundColor: isCustom ? scheme.tertiaryContainer : null,
                foregroundColor: isCustom
                    ? scheme.onTertiaryContainer
                    : scheme.onSurfaceVariant,
                side: BorderSide(
                  color: isCustom ? scheme.tertiary : scheme.outlineVariant,
                ),
              ),
              child: Row(
                children: [
                  Icon(icon, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      isCustom ? customLabel : label,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Icon(Icons.edit_outlined, size: 20),
                ],
              ),
            ),
          ),
        ),
        if (isCustom) ...[
          const SizedBox(width: 10),
          IconButton(
            onPressed: onReset,
            icon: const Icon(Icons.restore),
            iconSize: 26,
            tooltip: resetTooltip,
            style: IconButton.styleFrom(
              minimumSize: const Size(
                AppTheme.minTapTarget,
                AppTheme.minTapTarget,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
