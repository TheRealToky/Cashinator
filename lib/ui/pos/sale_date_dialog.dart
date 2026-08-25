import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_date.dart';
import '../theme.dart';

/// Picker for the business date a sale is recorded against.
///
/// A row of recent days rather than a calendar first, because backdating is
/// nearly always "the sale we missed yesterday" or "the Saturday the tablet was
/// flat" — days staff name by weekday, within the last week. The full calendar
/// is one tap further on for the rarer catch-up.
///
/// Only the past is offered. A sale cannot have happened tomorrow, and a
/// forward-dated one would sit ahead of the clock, quietly seeding a day's
/// order sequence and totals before that day opens.
class SaleDateDialog extends StatefulWidget {
  const SaleDateDialog({
    super.key,
    required this.today,
    required this.initial,
    this.title = defaultTitle,
    this.backdateNote = defaultBackdateNote,
  });

  /// Heading, and the calendar's help text. The back office's expense form
  /// reuses this dialog and renames it — the rules about which days may be
  /// picked are the same for money going out as for money coming in.
  static const String defaultTitle = 'Sale date';

  /// Shown once a day other than today is selected.
  static const String defaultBackdateNote =
      'This sale will be added to that day’s order numbers and day total, '
      'not today’s.';

  /// The current business day — the newest date that can be chosen.
  final DateTime today;

  /// The date the dialog opens on: the sale's current date.
  final DateTime initial;

  final String title;
  final String backdateNote;

  /// How far back a sale may be dated.
  ///
  /// Wide enough for a closed week or a tablet that spent a fortnight in a
  /// drawer, short enough that a mis-tap cannot land a sale in a month that has
  /// already been exported and reconciled on paper. Extending it is a one-line
  /// change here; nothing else reads the window.
  static const int maxBackdateDays = 30;

  /// How many recent days get their own button.
  static const int quickDayCount = 7;

  /// Shows the picker and resolves to the chosen date at local midnight, or
  /// `null` if cancelled.
  static Future<DateTime?> show(
    BuildContext context, {
    required DateTime today,
    required DateTime initial,
    String title = defaultTitle,
    String backdateNote = defaultBackdateNote,
  }) {
    return showDialog<DateTime>(
      context: context,
      builder: (_) => SaleDateDialog(
        today: today,
        initial: initial,
        title: title,
        backdateNote: backdateNote,
      ),
    );
  }

  @override
  State<SaleDateDialog> createState() => _SaleDateDialogState();
}

class _SaleDateDialogState extends State<SaleDateDialog> {
  late DateTime _selected = startOfDay(widget.initial);

  DateTime get _today => startOfDay(widget.today);

  DateTime get _earliest =>
      _today.subtract(const Duration(days: SaleDateDialog.maxBackdateDays));

  /// Today first, then backwards. Built by subtracting whole days from local
  /// midnight and re-truncating, so a DST change cannot repeat or skip a day.
  List<DateTime> get _quickDays => [
    for (var back = 0; back < SaleDateDialog.quickDayCount; back++)
      startOfDay(_today.subtract(Duration(days: back))),
  ];

  void _select(DateTime day) {
    setState(() => _selected = startOfDay(day));
  }

  Future<void> _openCalendar() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selected,
      firstDate: _earliest,
      lastDate: _today,
      helpText: widget.title,
      // The till has no hardware keyboard and typing a date is slower than
      // finding it; the calendar's day cells are already big enough to tap.
      initialEntryMode: DatePickerEntryMode.calendarOnly,
    );
    if (picked == null || !mounted) return;
    _select(picked);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isBackdated = !isSameDate(_selected, _today);

    return AlertDialog(
      title: Text(widget.title),
      contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _SelectedDateCard(date: _selected, today: _today),
              const SizedBox(height: 20),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  for (final day in _quickDays)
                    _DayButton(
                      label: formatRelativeDate(day, today: _today),
                      selected: isSameDate(day, _selected),
                      onPressed: () => _select(day),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: AppTheme.minTapTarget,
                child: OutlinedButton.icon(
                  onPressed: _openCalendar,
                  icon: const Icon(Icons.calendar_month_outlined, size: 22),
                  label: const Text('Another day…'),
                ),
              ),
              const SizedBox(height: 16),
              // Spelled out rather than left to be discovered at month end: a
              // backdated sale joins a day that may already have been counted.
              if (isBackdated)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.tertiaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 20,
                        color: scheme.onTertiaryContainer,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          widget.backdateNote,
                          style: TextStyle(
                            fontSize: 14,
                            color: scheme.onTertiaryContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 4),
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
          onPressed: () => Navigator.of(context).pop(_selected),
          child: Text('Set ${formatRelativeDate(_selected, today: _today)}'),
        ),
      ],
    );
  }
}

/// The read-out: what the sale is currently dated, in both namings so the
/// relative label and the calendar date confirm each other.
class _SelectedDateCard extends StatelessWidget {
  const _SelectedDateCard({required this.date, required this.today});

  final DateTime date;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isBackdated = !isSameDate(date, today);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
      decoration: BoxDecoration(
        color: isBackdated
            ? scheme.tertiaryContainer
            : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isBackdated ? scheme.tertiary : Colors.transparent,
          width: 2,
        ),
      ),
      child: Column(
        children: [
          Text(
            formatRelativeDate(date, today: today),
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w800,
              color: isBackdated
                  ? scheme.onTertiaryContainer
                  : scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            formatIsoDate(date),
            style: TextStyle(
              fontSize: 15,
              color: isBackdated
                  ? scheme.onTertiaryContainer
                  : scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// One recent day. The selected day is filled rather than outlined, so the
/// current choice is readable from standing height.
class _DayButton extends StatelessWidget {
  const _DayButton({
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final style = ButtonStyle(
      minimumSize: WidgetStatePropertyAll(Size(0, AppTheme.minTapTarget - 8)),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 16),
      ),
      textStyle: const WidgetStatePropertyAll(
        TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
    );

    void handle() {
      HapticFeedback.selectionClick();
      onPressed();
    }

    return selected
        ? FilledButton(onPressed: handle, style: style, child: Text(label))
        : OutlinedButton(onPressed: handle, style: style, child: Text(label));
  }
}
