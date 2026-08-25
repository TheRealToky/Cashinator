import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_date.dart';
import '../theme.dart';

/// Where the next typed digit lands.
///
/// Entry runs left to right and advances on its own, so "9 3 2" gives 09:32 and
/// "1 4 3 2" gives 14:32. A digit that could not start a real time is dropped
/// rather than shown, which is why the pad never has an error state to explain.
enum _Slot { hourFirst, hourSecond, minuteFirst, minuteSecond, done }

/// A time under construction: what the pad is currently showing.
class _Entry {
  const _Entry(this.hour, this.minute, this.slot);

  final int hour;
  final int minute;
  final _Slot slot;

  bool get isEditingHour =>
      slot == _Slot.hourFirst || slot == _Slot.hourSecond;
}

/// Keypad entry for the time a sale happened.
///
/// A register keypad rather than a clock dial: the counter is a standing,
/// one-handed environment where staff already type numbers all day, and four
/// taps beats dragging a hand around a dial. The quick nudges cover the case
/// this exists for — a sale rung up a few minutes after it actually happened.
class TimePadDialog extends StatefulWidget {
  const TimePadDialog({
    super.key,
    required this.day,
    required this.initial,
    this.title = defaultTitle,
  });

  /// Heading. The back office's expense form reuses this pad and renames it.
  static const String defaultTitle = 'Sale time';

  /// The business day the sale belongs to. Only the clock is editable; see
  /// [combineDateAndTime].
  final DateTime day;

  /// The time the pad opens on — the sale's current time.
  final TimeOfDay initial;

  final String title;

  /// Shows the pad and resolves to the chosen instant, or `null` if cancelled.
  static Future<DateTime?> show(
    BuildContext context, {
    required DateTime day,
    required TimeOfDay initial,
    String title = defaultTitle,
  }) {
    return showDialog<DateTime>(
      context: context,
      builder: (_) => TimePadDialog(day: day, initial: initial, title: title),
    );
  }

  @override
  State<TimePadDialog> createState() => _TimePadDialogState();
}

class _TimePadDialogState extends State<TimePadDialog> {
  /// The value the pad falls back to when nothing has been typed: the opening
  /// time, or whatever "Now" and the nudges last set.
  late int _baseHour = widget.initial.hour;
  late int _baseMinute = widget.initial.minute;

  /// Digits typed since the last reset. The displayed time is replayed from
  /// this string, so backspace is just "drop the last digit and replay" and
  /// cannot leave the pad in a state typing could not have produced.
  String _digits = '';

  _Entry get _entry => _digits.isEmpty
      ? _Entry(_baseHour, _baseMinute, _Slot.hourFirst)
      : _parseDigits(_digits)!;

  /// Replays [digits] through the slot machine above. Returns `null` if any
  /// digit is impossible at its position — 25 is not an hour, :7x is not a
  /// minute — which is how a keystroke gets rejected.
  static _Entry? _parseDigits(String digits) {
    var hour = 0;
    var minute = 0;
    var slot = _Slot.hourFirst;

    for (final char in digits.split('')) {
      final digit = int.parse(char);
      switch (slot) {
        case _Slot.hourFirst:
          hour = digit;
          // 3–9 cannot be the first of a two-digit hour, so it is the whole
          // hour and the minutes start straight away: "9 3 0" is 09:30.
          slot = digit >= 3 ? _Slot.minuteFirst : _Slot.hourSecond;
        case _Slot.hourSecond:
          final candidate = hour * 10 + digit;
          if (candidate > 23) return null;
          hour = candidate;
          slot = _Slot.minuteFirst;
        case _Slot.minuteFirst:
          if (digit > 5) return null;
          minute = digit;
          slot = _Slot.minuteSecond;
        case _Slot.minuteSecond:
          minute = minute * 10 + digit;
          slot = _Slot.done;
        case _Slot.done:
          return null;
      }
    }

    return _Entry(hour, minute, slot);
  }

  void _onDigit(int digit) {
    final current = _entry;
    final next = _parseDigits('$_digits$digit');

    setState(() {
      if (next != null) {
        _digits = '$_digits$digit';
      } else if (current.slot == _Slot.done) {
        // A complete time is on screen and they kept typing: start a fresh one
        // rather than making them clear it first.
        _digits = '$digit';
      }
      // Otherwise the digit cannot occur here at all — drop it.
    });
  }

  /// A dedicated "00" key: from "14" it lands on 14:00 in one tap, which is the
  /// shape most corrected times take.
  void _onDoubleZero() {
    _onDigit(0);
    _onDigit(0);
  }

  void _onBackspace() {
    if (_digits.isEmpty) return;
    setState(() {
      _digits = _digits.substring(0, _digits.length - 1);
    });
  }

  void _setTo(int hour, int minute) {
    setState(() {
      _baseHour = hour;
      _baseMinute = minute;
      _digits = '';
    });
  }

  void _useNow() {
    final now = DateTime.now();
    _setTo(now.hour, now.minute);
  }

  /// Shifts the displayed time by [deltaMinutes], clamped inside the day so a
  /// nudge can never quietly move the sale onto yesterday.
  void _nudge(int deltaMinutes) {
    final entry = _entry;
    final total = (entry.hour * 60 + entry.minute + deltaMinutes)
        .clamp(0, Duration.minutesPerDay - 1);
    _setTo(total ~/ 60, total % 60);
  }

  @override
  Widget build(BuildContext context) {
    final entry = _entry;
    final chosen = combineDateAndTime(widget.day, entry.hour, entry.minute);

    return AlertDialog(
      title: Text(widget.title),
      contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
      content: SizedBox(
        width: 340,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _TimeField(
                  label: 'Hour',
                  value: entry.hour,
                  active: entry.isEditingHour,
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10),
                  child: Text(
                    ':',
                    style: TextStyle(fontSize: 34, fontWeight: FontWeight.w700),
                  ),
                ),
                _TimeField(
                  label: 'Minute',
                  value: entry.minute,
                  active: !entry.isEditingHour,
                ),
              ],
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                _QuickButton(label: 'Now', onPressed: _useNow),
                _QuickButton(label: '−5 min', onPressed: () => _nudge(-5)),
                _QuickButton(label: '−15 min', onPressed: () => _nudge(-15)),
                _QuickButton(label: '−30 min', onPressed: () => _nudge(-30)),
              ],
            ),
            const SizedBox(height: 20),
            _Keypad(
              onDigit: _onDigit,
              onDoubleZero: _onDoubleZero,
              onBackspace: _onBackspace,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(chosen),
          child: Text('Set ${formatHourMinute(chosen)}'),
        ),
      ],
    );
  }
}

/// One half of the read-out. The active half is tinted so it is obvious where
/// the next digit will land.
class _TimeField extends StatelessWidget {
  const _TimeField({
    required this.label,
    required this.value,
    required this.active,
  });

  final String label;
  final int value;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        Container(
          width: 116,
          height: 88,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active
                ? scheme.primaryContainer
                : scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: active ? scheme.primary : Colors.transparent,
              width: 2,
            ),
          ),
          child: Text(
            value.toString().padLeft(2, '0'),
            style: TextStyle(
              fontSize: 42,
              fontWeight: FontWeight.w800,
              color:
                  active ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _QuickButton extends StatelessWidget {
  const _QuickButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: AppTheme.minTapTarget - 8,
      child: OutlinedButton(
        onPressed: () {
          HapticFeedback.selectionClick();
          onPressed();
        },
        style: OutlinedButton.styleFrom(
          minimumSize: Size.zero,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
        ),
        child: Text(label),
      ),
    );
  }
}

class _Keypad extends StatelessWidget {
  const _Keypad({
    required this.onDigit,
    required this.onDoubleZero,
    required this.onBackspace,
  });

  final ValueChanged<int> onDigit;
  final VoidCallback onDoubleZero;
  final VoidCallback onBackspace;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final row in const [
          [1, 2, 3],
          [4, 5, 6],
          [7, 8, 9],
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (final digit in row)
                  _PadKey(
                    onPressed: () => onDigit(digit),
                    child: Text('$digit', style: _keyTextStyle),
                  ),
              ],
            ),
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _PadKey(
              onPressed: onBackspace,
              tooltip: 'Delete a digit',
              child: const Icon(Icons.backspace_outlined, size: 24),
            ),
            _PadKey(
              onPressed: () => onDigit(0),
              child: const Text('0', style: _keyTextStyle),
            ),
            _PadKey(
              onPressed: onDoubleZero,
              tooltip: 'On the hour',
              child: const Text('00', style: _keyTextStyle),
            ),
          ],
        ),
      ],
    );
  }
}

const TextStyle _keyTextStyle =
    TextStyle(fontSize: 26, fontWeight: FontWeight.w700);

class _PadKey extends StatelessWidget {
  const _PadKey({
    required this.onPressed,
    required this.child,
    this.tooltip,
  });

  final VoidCallback onPressed;
  final Widget child;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final button = SizedBox(
      width: 96,
      height: AppTheme.minTapTarget,
      child: OutlinedButton(
        onPressed: () {
          HapticFeedback.selectionClick();
          onPressed();
        },
        style: OutlinedButton.styleFrom(
          padding: EdgeInsets.zero,
          minimumSize: Size.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: child,
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5),
      child: tooltip == null ? button : Tooltip(message: tooltip!, child: button),
    );
  }
}
