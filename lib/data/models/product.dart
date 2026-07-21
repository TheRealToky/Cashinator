import '../../core/app_exception.dart';

/// A sellable item in the catalogue.
///
/// [price] is whole RWF. Products are never hard-deleted — back office toggles
/// [active] instead, so historical orders keep referring to a row that exists.
class Product {
  const Product({
    required this.id,
    required this.name,
    required this.price,
    required this.active,
    this.category,
    this.sortOrder = 0,
  });

  final int? id;
  final String name;
  final int price;
  final String? category;
  final bool active;
  final int sortOrder;

  /// Validates user input before it reaches the database.
  ///
  /// Throws [ValidationException] with a message meant for the manager typing
  /// into the product form.
  void validate() {
    if (name.trim().isEmpty) {
      throw const ValidationException('Product name cannot be empty.');
    }
    if (name.trim().length > 80) {
      throw const ValidationException(
        'Product name is too long (80 characters maximum).',
      );
    }
    if (price < 0) {
      throw const ValidationException('Price cannot be negative.');
    }
    if (price > 10000000) {
      throw const ValidationException('Price looks wrong — check the amount.');
    }
  }

  Product copyWith({
    int? id,
    String? name,
    int? price,
    String? category,
    bool? active,
    int? sortOrder,
    bool clearCategory = false,
  }) {
    return Product(
      id: id ?? this.id,
      name: name ?? this.name,
      price: price ?? this.price,
      category: clearCategory ? null : (category ?? this.category),
      active: active ?? this.active,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }

  Map<String, Object?> toRow() => {
        if (id != null) 'id': id,
        'name': name.trim(),
        'price': price,
        'category': category?.trim(),
        'active': active ? 1 : 0,
        'sort_order': sortOrder,
      };

  factory Product.fromRow(Map<String, Object?> row) => Product(
        id: row['id'] as int?,
        name: row['name'] as String? ?? '',
        price: (row['price'] as int?) ?? 0,
        category: row['category'] as String?,
        active: (row['active'] as int? ?? 1) == 1,
        sortOrder: (row['sort_order'] as int?) ?? 0,
      );
}
