import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'data/db/app_database.dart';
import 'repositories/auth_repository.dart';
import 'repositories/expense_repository.dart';
import 'repositories/export_repository.dart';
import 'repositories/order_repository.dart';
import 'repositories/payment_method_repository.dart';
import 'repositories/product_repository.dart';
import 'repositories/production_repository.dart';
import 'repositories/unsold_repository.dart';
import 'state/cart_controller.dart';
import 'state/catalog_controller.dart';
import 'state/sample_controller.dart';
import 'ui/auth/pin_screen.dart';
import 'ui/theme.dart';

/// Wires the object graph and hands it to the widget tree.
///
/// Repositories are plain constructor-injected classes, so any of them can be
/// swapped for a fake in a widget test by overriding one provider.
class CashinatorApp extends StatelessWidget {
  const CashinatorApp({super.key, required this.database});

  final AppDatabase database;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<AppDatabase>.value(value: database),
        Provider<ProductRepository>(
          create: (_) => ProductRepository(database),
        ),
        Provider<PaymentMethodRepository>(
          create: (_) => PaymentMethodRepository(database),
        ),
        Provider<OrderRepository>(
          create: (_) => OrderRepository(database),
        ),
        Provider<ExpenseRepository>(
          create: (_) => ExpenseRepository(database),
        ),
        Provider<ProductionRepository>(
          create: (_) => ProductionRepository(database),
        ),
        Provider<UnsoldRepository>(
          create: (_) => UnsoldRepository(database),
        ),
        Provider<AuthRepository>(
          create: (_) => AuthRepository(database),
        ),
        ProxyProvider4<OrderRepository, ExpenseRepository, ProductionRepository,
            UnsoldRepository, ExportRepository>(
          update: (_, orders, expenses, production, unsold, __) =>
              ExportRepository(orders, expenses, production, unsold),
        ),
        // Keeps `previous`, so the held sample draws survive a rebuild — a new
        // controller here would silently redraw behind the manager's back.
        ProxyProvider<OrderRepository, SampleController>(
          update: (_, orders, previous) =>
              previous ?? SampleController(orders),
        ),
        ChangeNotifierProvider<CartController>(
          create: (_) => CartController(),
        ),
        ChangeNotifierProxyProvider2<ProductRepository,
            PaymentMethodRepository, CatalogController>(
          create: (context) => CatalogController(
            products: context.read<ProductRepository>(),
            paymentMethods: context.read<PaymentMethodRepository>(),
          ),
          update: (_, products, methods, previous) =>
              previous ??
              CatalogController(products: products, paymentMethods: methods),
        ),
      ],
      child: MaterialApp(
        title: 'Cashinator',
        theme: AppTheme.light(),
        debugShowCheckedModeBanner: false,
        home: const PinScreen(),
      ),
    );
  }
}
