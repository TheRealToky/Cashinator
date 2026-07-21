import 'package:sqflite/sqflite.dart';

import '../core/app_exception.dart';
import '../data/db/app_database.dart';
import '../data/models/payment_method.dart';

/// Payment method reads and writes.
///
/// Like products, methods are deactivated rather than deleted so historical
/// orders keep a valid foreign key.
class PaymentMethodRepository {
  PaymentMethodRepository(this._database);

  final AppDatabase _database;

  Database get _db => _database.db;

  /// Methods offered at the payment step.
  Future<List<PaymentMethod>> activeMethods() async {
    try {
      final rows = await _db.query(
        'payment_methods',
        where: 'active = 1',
        orderBy: 'sort_order ASC, name COLLATE NOCASE ASC',
      );
      return rows.map(PaymentMethod.fromRow).toList(growable: false);
    } on DatabaseException catch (error) {
      throw StorageException(
        'Could not load payment methods.',
        cause: error,
      );
    }
  }

  Future<List<PaymentMethod>> allMethods() async {
    try {
      final rows = await _db.query(
        'payment_methods',
        orderBy: 'active DESC, sort_order ASC, name COLLATE NOCASE ASC',
      );
      return rows.map(PaymentMethod.fromRow).toList(growable: false);
    } on DatabaseException catch (error) {
      throw StorageException(
        'Could not load payment methods.',
        cause: error,
      );
    }
  }

  Future<PaymentMethod> create(PaymentMethod method) async {
    method.validate();
    try {
      final id = await _db.insert(
        'payment_methods',
        method.toRow()..remove('id'),
      );
      return method.copyWith(id: id);
    } on DatabaseException catch (error) {
      // The NOCASE unique index is what rejects a second "momo".
      if (error.isUniqueConstraintError()) {
        throw ValidationException(
          'A payment method named "${method.name.trim()}" already exists.',
          cause: error,
        );
      }
      throw StorageException('Could not save the payment method.', cause: error);
    }
  }

  Future<PaymentMethod> update(PaymentMethod method) async {
    method.validate();
    final id = method.id;
    if (id == null) {
      throw const ValidationException(
        'Cannot update a payment method without an id.',
      );
    }

    try {
      final affected = await _db.update(
        'payment_methods',
        method.toRow()..remove('id'),
        where: 'id = ?',
        whereArgs: [id],
      );
      if (affected == 0) {
        throw const NotFoundException('That payment method no longer exists.');
      }
      return method;
    } on DatabaseException catch (error) {
      if (error.isUniqueConstraintError()) {
        throw ValidationException(
          'A payment method named "${method.name.trim()}" already exists.',
          cause: error,
        );
      }
      throw StorageException('Could not save the payment method.', cause: error);
    }
  }

  /// Deactivating the last active method would leave staff unable to complete a
  /// sale, so that case is refused.
  Future<void> setActive(int methodId, {required bool active}) async {
    if (!active) {
      final remaining = await activeMethods();
      final wouldBeEmpty =
          remaining.length <= 1 && remaining.any((m) => m.id == methodId);
      if (wouldBeEmpty) {
        throw const ConflictException(
          'At least one payment method must stay active — staff could not '
          'complete a sale otherwise.',
        );
      }
    }

    try {
      final affected = await _db.update(
        'payment_methods',
        {'active': active ? 1 : 0},
        where: 'id = ?',
        whereArgs: [methodId],
      );
      if (affected == 0) {
        throw const NotFoundException('That payment method no longer exists.');
      }
    } on DatabaseException catch (error) {
      throw StorageException(
        'Could not change the payment method status.',
        cause: error,
      );
    }
  }
}
