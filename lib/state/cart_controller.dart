import 'package:flutter/foundation.dart';

import '../data/models/product.dart';
import '../repositories/order_repository.dart';

/// One product staged in the cart, with a running quantity.
class CartItem {
  CartItem({required this.product, this.qty = 1});

  final Product product;
  int qty;

  int get lineTotal => qty * product.price;
}

/// The in-progress sale.
///
/// Lives only in memory: nothing is written until the cashier confirms payment,
/// so an abandoned cart leaves no trace in the database.
class CartController extends ChangeNotifier {
  final List<CartItem> _items = [];

  List<CartItem> get items => List.unmodifiable(_items);

  bool get isEmpty => _items.isEmpty;
  bool get isNotEmpty => _items.isNotEmpty;

  /// Distinct products in the cart.
  int get lineCount => _items.length;

  /// Total units, which is what the cashier reads out loud.
  int get itemCount => _items.fold(0, (sum, item) => sum + item.qty);

  int get total => _items.fold(0, (sum, item) => sum + item.lineTotal);

  /// Adds one of [product], or bumps the quantity if it is already there.
  ///
  /// This is the tap handler for the product grid — repeated taps on the same
  /// tile increment rather than creating duplicate lines.
  void add(Product product) {
    final existing = _findByProductId(product.id);
    if (existing != null) {
      existing.qty++;
    } else {
      _items.add(CartItem(product: product));
    }
    notifyListeners();
  }

  /// Removes one unit, dropping the line entirely when it reaches zero.
  void decrement(Product product) {
    final existing = _findByProductId(product.id);
    if (existing == null) return;

    existing.qty--;
    if (existing.qty <= 0) {
      _items.remove(existing);
    }
    notifyListeners();
  }

  void removeLine(Product product) {
    _items.removeWhere((item) => item.product.id == product.id);
    notifyListeners();
  }

  /// Sets an explicit quantity, for the keypad in the cart panel.
  void setQty(Product product, int qty) {
    final existing = _findByProductId(product.id);
    if (existing == null) return;

    if (qty <= 0) {
      _items.remove(existing);
    } else {
      // Guards against a stuck key or a mis-tap turning into 9 999 croissants.
      existing.qty = qty > 999 ? 999 : qty;
    }
    notifyListeners();
  }

  int qtyOf(Product product) => _findByProductId(product.id)?.qty ?? 0;

  void clear() {
    if (_items.isEmpty) return;
    _items.clear();
    notifyListeners();
  }

  /// Snapshots the cart into the shape [OrderRepository.createOrder] wants.
  ///
  /// Prices are copied here, so an edit to the catalogue between building the
  /// cart and confirming cannot change what the customer was quoted.
  List<DraftLine> toDraftLines() => _items
      .map((item) => DraftLine(
            productId: item.product.id,
            productName: item.product.name,
            unitPrice: item.product.price,
            qty: item.qty,
          ))
      .toList(growable: false);

  CartItem? _findByProductId(int? productId) {
    if (productId == null) return null;
    for (final item in _items) {
      if (item.product.id == productId) return item;
    }
    return null;
  }
}
