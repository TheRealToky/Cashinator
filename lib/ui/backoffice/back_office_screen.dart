import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_date.dart';
import '../../core/app_exception.dart';
import '../../core/money.dart';
import '../../repositories/auth_repository.dart';
import '../../repositories/order_repository.dart';
import '../widgets/async_value_view.dart';
import 'change_pin_screen.dart';
import 'expenses_screen.dart';
import 'export_screen.dart';
import 'order_history_screen.dart';
import 'payment_methods_screen.dart';
import 'production_history_screen.dart';
import 'production_screen.dart';
import 'products_screen.dart';
import 'sample_screen.dart';
import 'unsold_history_screen.dart';
import 'unsold_screen.dart';

/// Management landing screen: today at a glance, then the tools this role is
/// allowed to open.
///
/// The same screen serves the full [UserRole.manager] and the limited
/// [UserRole.supervisor]; the [role] decides which tiles (and the default-PIN
/// warning, which only the manager can act on) are shown.
class BackOfficeScreen extends StatefulWidget {
  const BackOfficeScreen({super.key, required this.role});

  final UserRole role;

  @override
  State<BackOfficeScreen> createState() => _BackOfficeScreenState();
}

class _BackOfficeScreenState extends State<BackOfficeScreen> {
  DayTotals? _totals;
  String? _error;
  bool _loading = true;
  bool _defaultPinsInUse = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final orders = context.read<OrderRepository>();
      final auth = context.read<AuthRepository>();

      final totals = await orders.totalsForDate(DateTime.now());

      // The banner offers a shortcut to the Change PIN screen, so it is only
      // meaningful for a role that can actually change PINs.
      var defaultPinsInUse = false;
      if (widget.role.canChangePins) {
        for (final role in UserRole.values) {
          if (await auth.isUsingDefaultPin(role)) {
            defaultPinsInUse = true;
            break;
          }
        }
      }

      if (!mounted) return;
      setState(() {
        _totals = totals;
        _defaultPinsInUse = defaultPinsInUse;
        _loading = false;
      });
    } on AppException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _loading = false;
      });
    }
  }

  Future<void> _openTool(Widget screen) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => screen),
    );
    // Totals and the PIN warning may both have changed while away.
    if (mounted) unawaited(_load());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(
          widget.role == UserRole.manager
              ? 'Back office'
              : 'Back office · ${widget.role.label}',
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: OutlinedButton.icon(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.lock_outline),
              label: const Text('Sign out'),
            ),
          ),
        ],
      ),
      body: _loading
          ? const LoadingView()
          : _error != null
              ? ErrorView(message: _error!, onRetry: _load)
              : _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    final totals = _totals;
    final role = widget.role;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_defaultPinsInUse) ...[
            _DefaultPinWarning(
              onChangePin: () => _openTool(const ChangePinScreen()),
            ),
            const SizedBox(height: 20),
          ],
          if (totals != null) _TodayCard(totals: totals),
          const SizedBox(height: 24),
          const Text(
            'Manage',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              if (role.canManageProducts)
                _ToolTile(
                  icon: Icons.bakery_dining_outlined,
                  label: 'Products',
                  description: 'Add, edit, deactivate',
                  onTap: () => _openTool(const ProductsScreen()),
                ),
              if (role.canManagePaymentMethods)
                _ToolTile(
                  icon: Icons.payments_outlined,
                  label: 'Payment methods',
                  description: 'Cash, MoMo, Card and more',
                  onTap: () => _openTool(const PaymentMethodsScreen()),
                ),
              if (role.canManageOrders)
                _ToolTile(
                  icon: Icons.receipt_long_outlined,
                  label: 'Order history',
                  description: 'Browse and void orders',
                  onTap: () => _openTool(const OrderHistoryScreen()),
                ),
              if (role.canManageExpenses)
                _ToolTile(
                  icon: Icons.account_balance_wallet_outlined,
                  label: 'Expenses',
                  description: 'Record what the shop spends',
                  onTap: () => _openTool(const ExpensesScreen()),
                ),
              if (role.canRecordProduction)
                _ToolTile(
                  icon: Icons.inventory_2_outlined,
                  label: 'Record production',
                  description: 'Log what the kitchen produced',
                  onTap: () => _openTool(const ProductionScreen()),
                ),
              if (role.canViewProductionHistory)
                _ToolTile(
                  icon: Icons.precision_manufacturing_outlined,
                  label: 'Production history',
                  description: 'Browse daily production logs',
                  onTap: () => _openTool(const ProductionHistoryScreen()),
                ),
              if (role.canRecordUnsold)
                _ToolTile(
                  icon: Icons.remove_shopping_cart_outlined,
                  label: 'Record unsold',
                  description: 'Log end-of-day unsold products',
                  onTap: () => _openTool(const UnsoldScreen()),
                ),
              if (role.canViewUnsoldHistory)
                _ToolTile(
                  icon: Icons.event_busy_outlined,
                  label: 'Unsold history',
                  description: 'Browse daily unsold logs',
                  onTap: () => _openTool(const UnsoldHistoryScreen()),
                ),
              if (role.canViewSample)
                _ToolTile(
                  icon: Icons.shuffle,
                  label: 'Sample',
                  description: 'A random 45% of a day’s sales',
                  onTap: () => _openTool(const SampleScreen()),
                ),
              if (role.canExport)
                _ToolTile(
                  icon: Icons.table_view_outlined,
                  label: 'Excel export',
                  description: 'Sales for a date range',
                  onTap: () => _openTool(const ExportScreen()),
                ),
              if (role.canChangePins)
                _ToolTile(
                  icon: Icons.password_outlined,
                  label: 'Change PIN',
                  description: 'Front office, back office or supervisor',
                  onTap: () => _openTool(const ChangePinScreen()),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DefaultPinWarning extends StatelessWidget {
  const _DefaultPinWarning({required this.onChangePin});

  final VoidCallback onChangePin;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded,
              size: 32, color: scheme.onErrorContainer),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              'This tablet still uses a PIN that shipped with the app. '
              'Anyone who knows it can open the back office.',
              style: TextStyle(fontSize: 17, color: scheme.onErrorContainer),
            ),
          ),
          const SizedBox(width: 16),
          FilledButton(
            onPressed: onChangePin,
            child: const Text('Change PIN'),
          ),
        ],
      ),
    );
  }
}

class _TodayCard extends StatelessWidget {
  const _TodayCard({required this.totals});

  final DayTotals totals;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Today · ${formatIsoDate(totals.date)}',
            style: TextStyle(fontSize: 16, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 40,
            runSpacing: 16,
            children: [
              _Stat(
                label: 'Sales',
                value: formatRwfWithUnit(totals.revenue),
                emphasise: true,
              ),
              _Stat(label: 'Orders', value: '${totals.orderCount}'),
              if (totals.voidedCount > 0)
                _Stat(
                  label: 'Voided',
                  value: '${totals.voidedCount}',
                  warn: true,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.label,
    required this.value,
    this.emphasise = false,
    this.warn = false,
  });

  final String label;
  final String value;
  final bool emphasise;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 15, color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: emphasise ? 32 : 26,
            fontWeight: FontWeight.w800,
            color: warn
                ? scheme.error
                : emphasise
                    ? scheme.primary
                    : scheme.onSurface,
          ),
        ),
      ],
    );
  }
}

class _ToolTile extends StatelessWidget {
  const _ToolTile({
    required this.icon,
    required this.label,
    required this.description,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return SizedBox(
      width: 260,
      height: 150,
      child: Material(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(icon, size: 34, color: scheme.primary),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      description,
                      style: TextStyle(
                        fontSize: 14,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
