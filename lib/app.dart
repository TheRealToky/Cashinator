import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'data/db/app_database.dart';
import 'repositories/auth_repository.dart';
import 'repositories/export_repository.dart';
import 'repositories/order_repository.dart';
import 'repositories/payment_method_repository.dart';
import 'repositories/product_repository.dart';
import 'state/cart_controller.dart';
import 'state/catalog_controller.dart';
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
        Provider<AuthRepository>(
          create: (_) => AuthRepository(database),
        ),
        ProxyProvider<OrderRepository, ExportRepository>(
          update: (_, orders, __) => ExportRepository(orders),
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
