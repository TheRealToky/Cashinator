import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_date.dart';
import '../../core/app_exception.dart';
import '../../repositories/export_repository.dart';
import '../widgets/async_value_view.dart';

/// Date-range picker plus the export trigger.
class ExportScreen extends StatefulWidget {
  const ExportScreen({super.key});

  @override
  State<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends State<ExportScreen> {
  late DateTime _from;
  late DateTime _to;
  bool _busy = false;
  ExportResult? _result;

  @override
  void initState() {
    super.initState();
    // Defaults to today, the most common export. "This month" is one tap away.
    final today = startOfDay(DateTime.now());
    _from = today;
    _to = today;
  }

  void _applyPreset({required DateTime from, required DateTime to}) {
    setState(() {
      _from = from;
      _to = to;
      _result = null;
    });
  }

  Future<void> _pick({required bool isStart}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isStart ? _from : _to,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked == null) return;

    setState(() {
      final day = startOfDay(picked);
      if (isStart) {
        _from = day;
        // Keep the range valid rather than rejecting the tap afterwards.
        if (_to.isBefore(_from)) _to = _from;
      } else {
        _to = day;
        if (_to.isBefore(_from)) _from = _to;
      }
      _result = null;
    });
  }

  Future<void> _export() async {
    setState(() {
      _busy = true;
      _result = null;
    });

    try {
      final result = await context
          .read<ExportRepository>()
          .exportRange(from: _from, to: _to);
      if (!mounted) return;
      setState(() => _result = result);
      showAppSnackBar(context, 'Exported ${result.fileName}.');
    } on AppException catch (error) {
      if (!mounted) return;
      showAppSnackBar(context, error.message, isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final today = startOfDay(DateTime.now());

    return Scaffold(
      appBar: AppBar(title: const Text('Excel export')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Date range',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _PresetChip(
                  label: 'Today',
                  onTap: () => _applyPreset(from: today, to: today),
                ),
                _PresetChip(
                  label: 'Yesterday',
                  onTap: () {
                    final yesterday =
                        startOfDay(today.subtract(const Duration(hours: 23)));
                    _applyPreset(from: yesterday, to: yesterday);
                  },
                ),
                _PresetChip(
                  label: 'This month',
                  onTap: () =>
                      _applyPreset(from: startOfMonth(today), to: today),
                ),
              ],
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: _DateField(
                    label: 'From',
                    value: _from,
                    onTap: () => _pick(isStart: true),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _DateField(
                    label: 'To',
                    value: _to,
                    onTap: () => _pick(isStart: false),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 28),
            SizedBox(
              height: 64,
              child: FilledButton.icon(
                onPressed: _busy ? null : _export,
                icon: _busy
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 3,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.download, size: 26),
                label: Text(_busy ? 'Generating…' : 'Generate Excel file'),
              ),
            ),
            if (_result != null) ...[
              const SizedBox(height: 28),
              _ResultCard(result: _result!),
            ],
            const SizedBox(height: 28),
            const _FormatNote(),
          ],
        ),
      ),
    );
  }
}

class _PresetChip extends StatelessWidget {
  const _PresetChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      label: Text(label, style: const TextStyle(fontSize: 16)),
      onPressed: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final DateTime value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          child: Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 14,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    formatIsoDate(value),
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Icon(Icons.calendar_today_outlined, color: scheme.primary),
            ],
          ),
        ),
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.result});

  final ExportResult result;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.check_circle_outline,
                  color: scheme.onPrimaryContainer, size: 28),
              const SizedBox(width: 12),
              Text(
                'Export ready',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: scheme.onPrimaryContainer,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            '${result.orderCount} order${result.orderCount == 1 ? '' : 's'} · '
            '${result.lineCount} line${result.lineCount == 1 ? '' : 's'} · '
            '${result.dayCount} day${result.dayCount == 1 ? '' : 's'}',
            style: TextStyle(fontSize: 17, color: scheme.onPrimaryContainer),
          ),
          const SizedBox(height: 10),
          SelectableText(
            result.file.path,
            style: TextStyle(fontSize: 14, color: scheme.onPrimaryContainer),
          ),
        ],
      ),
    );
  }
}

class _FormatNote extends StatelessWidget {
  const _FormatNote();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: scheme.primary, size: 24),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              'The file keeps the layout the existing ledger exports use: a '
              '"Sales Lines" sheet with one row per item, and a "Day Summary" '
              'sheet with one row per day. Voided orders stay visible in Sales '
              'Lines but are left out of the summary totals.',
              style: TextStyle(fontSize: 15, color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}
