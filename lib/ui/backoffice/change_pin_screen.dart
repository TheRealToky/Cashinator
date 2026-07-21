import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/app_exception.dart';
import '../../repositories/auth_repository.dart';
import '../widgets/async_value_view.dart';

/// Sets a new PIN for either role.
class ChangePinScreen extends StatefulWidget {
  const ChangePinScreen({super.key});

  @override
  State<ChangePinScreen> createState() => _ChangePinScreenState();
}

class _ChangePinScreenState extends State<ChangePinScreen> {
  final _formKey = GlobalKey<FormState>();
  final _pin = TextEditingController();
  final _confirm = TextEditingController();

  UserRole _role = UserRole.staff;
  bool _busy = false;

  @override
  void dispose() {
    _pin.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _busy = true);
    try {
      await context
          .read<AuthRepository>()
          .changePin(role: _role, newPin: _pin.text.trim());
      if (!mounted) return;
      showAppSnackBar(context, '${_role.label} PIN updated.');
      Navigator.of(context).pop();
    } on AppException catch (error) {
      if (!mounted) return;
      showAppSnackBar(context, error.message, isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Change PIN')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Which PIN?',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 14),
                  SegmentedButton<UserRole>(
                    segments: [
                      for (final role in UserRole.values)
                        ButtonSegment(
                          value: role,
                          label: Text(
                            role.label,
                            style: const TextStyle(fontSize: 16),
                          ),
                        ),
                    ],
                    selected: {_role},
                    onSelectionChanged: (selection) =>
                        setState(() => _role = selection.first),
                  ),
                  const SizedBox(height: 28),
                  TextFormField(
                    controller: _pin,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(8),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'New PIN',
                      helperText: '4 to 8 digits',
                    ),
                    style: const TextStyle(fontSize: 20, letterSpacing: 6),
                    validator: (value) {
                      final pin = (value ?? '').trim();
                      if (pin.length < 4) return 'At least 4 digits.';
                      if (pin.length > 8) return 'At most 8 digits.';
                      return null;
                    },
                  ),
                  const SizedBox(height: 18),
                  TextFormField(
                    controller: _confirm,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(8),
                    ],
                    decoration: const InputDecoration(labelText: 'Repeat PIN'),
                    style: const TextStyle(fontSize: 20, letterSpacing: 6),
                    validator: (value) => (value ?? '').trim() != _pin.text.trim()
                        ? 'The two PINs do not match.'
                        : null,
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    height: 60,
                    child: FilledButton(
                      onPressed: _busy ? null : _submit,
                      child: Text(_busy ? 'Saving…' : 'Save PIN'),
                    ),
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
