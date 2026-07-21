import 'package:flutter/foundation.dart';

import '../core/app_exception.dart';
import '../data/models/payment_method.dart';
import '../data/models/product.dart';
import '../repositories/payment_method_repository.dart';
import '../repositories/product_repository.dart';

/// Loading state for a screen backed by the catalogue.
enum LoadState { idle, loading, ready, failed }

/// Holds the product and payment-method lists the till screen renders.
///
/// Both are small (tens of rows) and change rarely, so they are loaded once and
/// refreshed explicitly after a back-office edit rather than re-queried per
/// frame.
class CatalogController extends ChangeNotifier {
  CatalogController({
    required ProductRepository products,
    required PaymentMethodRepository paymentMethods,
  })  : _products = products,
        _paymentMethods = paymentMethods;

  final ProductRepository _products;
  final PaymentMethodRepository _paymentMethods;

  LoadState _state = LoadState.idle;
  LoadState get state => _state;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  List<Product> _activeProducts = const [];
  List<Product> get activeProducts => _activeProducts;

  List<PaymentMethod> _activeMethods = const [];
  List<PaymentMethod> get activeMethods => _activeMethods;

  List<String> _categories = const [];
  List<String> get categories => _categories;

  String? _selectedCategory;
  String? get selectedCategory => _selectedCategory;

  /// Products matching the current category filter.
  List<Product> get visibleProducts {
    final category = _selectedCategory;
    if (category == null) return _activeProducts;
    return _activeProducts
        .where((product) => product.category == category)
        .toList(growable: false);
  }

  void selectCategory(String? category) {
    if (_selectedCategory == category) return;
    _selectedCategory = category;
    notifyListeners();
  }

  Future<void> load() async {
    _state = LoadState.loading;
    _errorMessage = null;
    notifyListeners();

    try {
      final results = await Future.wait([
        _products.activeProducts(),
        _paymentMethods.activeMethods(),
        _products.activeCategories(),
      ]);

      _activeProducts = results[0] as List<Product>;
      _activeMethods = results[1] as List<PaymentMethod>;
      _categories = results[2] as List<String>;

      // A filter pointing at a category the manager just emptied would show a
      // blank grid with no obvious cause.
      if (_selectedCategory != null &&
          !_categories.contains(_selectedCategory)) {
        _selectedCategory = null;
      }

      _state = LoadState.ready;
    } on AppException catch (error) {
      _errorMessage = error.message;
      _state = LoadState.failed;
    } finally {
      notifyListeners();
    }
  }

  /// Re-reads the catalogue after a back-office change.
  Future<void> refresh() => load();
}
