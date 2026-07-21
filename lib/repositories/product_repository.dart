import 'package:sqflite/sqflite.dart';

import '../core/app_exception.dart';
import '../data/db/app_database.dart';
import '../data/models/product.dart';

/// Catalogue reads and writes.
///
/// Products are never deleted. `deactivate` hides a product from the sale grid
/// while leaving it joinable from historical orders.
class ProductRepository {
  ProductRepository(this._database);

  final AppDatabase _database;

  Database get _db => _database.db;

  /// Products shown on the sale grid, in the order management arranged them.
  Future<List<Product>> activeProducts() async {
    try {
      final rows = await _db.query(
        'products',
        where: 'active = 1',
        orderBy: 'sort_order ASC, name COLLATE NOCASE ASC',
      );
      return rows.map(Product.fromRow).toList(growable: false);
    } on DatabaseException catch (error) {
      throw StorageException('Could not load the product list.', cause: error);
    }
  }

  /// Every product including deactivated ones, for the back-office list.
  Future<List<Product>> allProducts() async {
    try {
      final rows = await _db.query(
        'products',
        orderBy: 'active DESC, sort_order ASC, name COLLATE NOCASE ASC',
      );
      return rows.map(Product.fromRow).toList(growable: false);
    } on DatabaseException catch (error) {
      throw StorageException('Could not load the product list.', cause: error);
    }
  }

  /// Distinct category names among active products, for grid filtering.
  Future<List<String>> activeCategories() async {
    try {
      final rows = await _db.rawQuery(
        '''
        SELECT DISTINCT category FROM products
        WHERE active = 1 AND category IS NOT NULL AND TRIM(category) <> ''
        ORDER BY category COLLATE NOCASE ASC
        ''',
      );
      return rows
          .map((row) => row['category'] as String)
          .toList(growable: false);
    } on DatabaseException catch (error) {
      throw StorageException('Could not load categories.', cause: error);
    }
  }

  Future<Product> findById(int id) async {
    try {
      final rows = await _db.query(
        'products',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (rows.isEmpty) {
        throw const NotFoundException('That product no longer exists.');
      }
      return Product.fromRow(rows.first);
    } on DatabaseException catch (error) {
      throw StorageException('Could not load the product.', cause: error);
    }
  }

  /// Inserts [product] and returns it with its assigned id.
  Future<Product> create(Product product) async {
    product.validate();
    try {
      final id = await _db.insert('products', product.toRow()..remove('id'));
      return product.copyWith(id: id);
    } on DatabaseException catch (error) {
      throw StorageException('Could not save the product.', cause: error);
    }
  }

  Future<Product> update(Product product) async {
    product.validate();
    final id = product.id;
    if (id == null) {
      throw const ValidationException('Cannot update a product without an id.');
    }

    try {
      final affected = await _db.update(
        'products',
        product.toRow()..remove('id'),
        where: 'id = ?',
        whereArgs: [id],
      );
      if (affected == 0) {
        throw const NotFoundException('That product no longer exists.');
      }
      return product;
    } on DatabaseException catch (error) {
      throw StorageException('Could not save the product.', cause: error);
    }
  }

  /// Hides [product] from the sale grid. Existing orders are untouched.
  Future<void> setActive(int productId, {required bool active}) async {
    try {
      final affected = await _db.update(
        'products',
        {'active': active ? 1 : 0},
        where: 'id = ?',
        whereArgs: [productId],
      );
      if (affected == 0) {
        throw const NotFoundException('That product no longer exists.');
      }
    } on DatabaseException catch (error) {
      throw StorageException(
        'Could not change the product status.',
        cause: error,
      );
    }
  }

  /// Persists a manual reordering of the sale grid.
  Future<void> reorder(List<int> productIdsInOrder) async {
    await _database.transaction(
      (txn) async {
        for (var index = 0; index < productIdsInOrder.length; index++) {
          await txn.update(
            'products',
            {'sort_order': index},
            where: 'id = ?',
            whereArgs: [productIdsInOrder[index]],
          );
        }
      },
      failureMessage: 'Could not save the new product order.',
    );
  }
}
