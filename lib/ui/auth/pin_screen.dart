import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/app_exception.dart';
import '../../repositories/auth_repository.dart';
import '../../state/cart_controller.dart';
import '../backoffice/back_office_screen.dart';
import '../pos/pos_screen.dart';

/// The lock screen, and the only entry point into the app.
///
/// One keypad serves both roles: the PIN itself decides whether the user lands
/// on the till or in the back office, so nobody has to pick a mode first.
class PinScreen extends StatefulWidget {
  const PinScreen({super.key});

  @override
  State<PinScreen> createState() => _PinScreenState();
}

class _PinScreenState extends State<PinScreen> {
  static const int _maxPinLength = 8;

  String _entered = '';
  bool _checking = false;
  String? _error;

  void _append(String digit) {
    if (_checking || _entered.length >= _maxPinLength) return;
    HapticFeedback.selectionClick();
    setState(() {
      _entered += digit;
      _error = null;
    });
  }

  void _backspace() {
    if (_checking || _entered.isEmpty) return;
    HapticFeedback.selectionClick();
    setState(() {
      _entered = _entered.substring(0, _entered.length - 1);
      _error = null;
    });
  }

  Future<void> _submit() async {
    if (_checking || _entered.length < 4) return;

    setState(() {
      _checking = true;
      _error = null;
    });

    try {
      final role = await context.read<AuthRepository>().authenticate(_entered);
      if (!mounted) return;

      if (role == null) {
        unawaited(HapticFeedback.heavyImpact());
        setState(() {
          _error = 'That PIN was not recognised.';
          _entered = '';
          _checking = false;
        });
        return;
      }

      // A new session always starts with an empty cart, so a half-built sale
      // from the previous shift can never be attributed to whoever logs in.
      context.read<CartController>().clear();

      final destination = switch (role) {
        UserRole.staff => const PosScreen(),
        UserRole.manager || UserRole.supervisor => BackOfficeScreen(role: role),
      };

      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => destination),
      );

      // Returning here means the user logged out; reset for the next person.
      if (!mounted) return;
      setState(() {
        _entered = '';
        _checking = false;
        _error = null;
      });
    } on AppException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _checking = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.bakery_dining_outlined,
                    size: 56,
                    color: scheme.primary,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Cashinator',
                    style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Enter your PIN',
                    style: TextStyle(
                      fontSize: 17,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 24),
                  _PinDots(
                    length: _entered.length,
                    hasError: _error != null,
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    height: 26,
                    child: _error == null
                        ? null
                        : Text(
                            _error!,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 16,
                              color: scheme.error,
                            ),
                          ),
                  ),
                  const SizedBox(height: 10),
                  _Keypad(
                    enabled: !_checking,
                    onDigit: _append,
                    onBackspace: _backspace,
                    onSubmit: _submit,
                    canSubmit: _entered.length >= 4,
                    busy: _checking,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Filled dots showing how many digits have been entered, without revealing
/// the PIN to anyone standing at the counter.
class _PinDots extends StatelessWidget {
  const _PinDots({required this.length, required this.hasError});

  final int length;
  final bool hasError;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(8, (index) {
        final filled = index < length;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          margin: const EdgeInsets.symmetric(horizontal: 7),
          width: filled ? 18 : 14,
          height: filled ? 18 : 14,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: filled
                ? (hasError ? scheme.error : scheme.primary)
                : scheme.outlineVariant,
          ),
        );
      }),
    );
  }
}

class _Keypad extends StatelessWidget {
  const _Keypad({
    required this.enabled,
    required this.onDigit,
    required this.onBackspace,
    required this.onSubmit,
    required this.canSubmit,
    required this.busy,
  });

  final bool enabled;
  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;
  final VoidCallback onSubmit;
  final bool canSubmit;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final row in const [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (final digit in row)
                  _KeypadButton(
                    label: digit,
                    onPressed: enabled ? () => onDigit(digit) : null,
                  ),
              ],
            ),
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _KeypadButton(
              icon: Icons.backspace_outlined,
              onPressed: enabled ? onBackspace : null,
              tooltip: 'Delete last digit',
            ),
            _KeypadButton(
              label: '0',
              onPressed: enabled ? () => onDigit('0') : null,
            ),
            _KeypadButton(
              icon: Icons.arrow_forward,
              filled: true,
              busy: busy,
              onPressed: enabled && canSubmit ? onSubmit : null,
              tooltip: 'Sign in',
            ),
          ],
        ),
      ],
    );
  }
}

class _KeypadButton extends StatelessWidget {
  const _KeypadButton({
    this.label,
    this.icon,
    this.onPressed,
    this.filled = false,
    this.busy = false,
    this.tooltip,
  });

  final String? label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool filled;
  final bool busy;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    // Generously oversized: these are hit with a thumb, quickly, all day.
    const double size = 84;

    final child = busy
        ? const SizedBox(
            width: 26,
            height: 26,
            child: CircularProgressIndicator(strokeWidth: 3),
          )
        : icon != null
            ? Icon(icon, size: 30)
            : Text(
                label ?? '',
                style: const TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w600,
                ),
              );

    final button = SizedBox(
      width: size,
      height: size,
      child: filled
          ? FilledButton(
              onPressed: onPressed,
              style: FilledButton.styleFrom(
                shape: const CircleBorder(),
                padding: EdgeInsets.zero,
                minimumSize: const Size(size, size),
              ),
              child: child,
            )
          : OutlinedButton(
              onPressed: onPressed,
              style: OutlinedButton.styleFrom(
                shape: const CircleBorder(),
                padding: EdgeInsets.zero,
                minimumSize: const Size(size, size),
                foregroundColor: scheme.onSurface,
              ),
              child: child,
            ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: tooltip == null ? button : Tooltip(message: tooltip!, child: button),
    );
  }
}
