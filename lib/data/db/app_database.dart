import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../../core/app_exception.dart';
import 'schema.dart';

/// Owns the single SQLite connection and its lifecycle.
///
/// Everything above this class talks to repositories, not to sqflite. The only
/// reason a widget would ever touch [AppDatabase] is to open it at startup.
class AppDatabase {
  AppDatabase._(this._db);

  final Database _db;

  Database get db => _db;

  static const String defaultFileName = 'cashinator.db';

  /// Default PINs written on first launch.
  ///
  /// These are deliberately obvious, and the back office has a "Change PIN"
  /// screen. Ship the tablet with these changed.
  static const String defaultStaffPin = '1234';
  static const String defaultManagerPin = '4321';
  static const String defaultSupervisorPin = '9876';

  /// Opens (and if needed creates) the database.
  ///
  /// Pass [fileName] `:memory:` in tests to get an isolated throwaway instance.
  static Future<AppDatabase> open({
    String? fileName,
    String? directoryOverride,
  }) async {
    final name = fileName ?? defaultFileName;

    try {
      final String path;
      if (name == inMemoryDatabasePath) {
        path = name;
      } else {
        final base = directoryOverride ?? await getDatabasesPath();
        path = p.join(base, name);
      }

      final database = await openDatabase(
        path,
        version: kSchemaVersion,
        onConfigure: (db) async {
          // order_lines -> orders cascade only works with this switched on, and
          // sqflite leaves it off by default.
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (db, version) async {
          final batch = db.batch();
          for (final statement in kCreateStatements) {
            batch.execute(statement);
          }
          await batch.commit(noResult: true);
          await _seed(db);
        },
        onUpgrade: _migrate,
      );

      return AppDatabase._(database);
    } on DatabaseException catch (error) {
      throw StorageException(
        'Could not open the local database. Restart the app; if this keeps '
        'happening the device storage may be full.',
        cause: error,
      );
    }
  }

  static Future<void> _migrate(Database db, int from, int to) async {
    // Each block brings a database one version forward, in order, so a device
    // several versions behind is upgraded step by step.
    if (from < 2) {
      final batch = db.batch();
      for (final statement in kMigrateV2Statements) {
        batch.execute(statement);
      }
      await batch.commit(noResult: true);

      // The supervisor arrives on the shipped default PIN; the back office
      // changes it from the Change PIN screen. Ignore a conflict so re-running
      // the migration can't fail on the unique role.
      final supervisor = hashPin(defaultSupervisorPin);
      await db.insert(
        'app_users',
        {
          'role': 'supervisor',
          'pin_hash': supervisor.hash,
          'pin_salt': supervisor.salt,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
  }

  static Future<void> _seed(Database db) async {
    final batch = db.batch();

    for (final method in kSeedPaymentMethods) {
      batch.insert('payment_methods', method);
    }
    for (final product in kSeedProducts) {
      batch.insert('products', {...product, 'active': 1});
    }

    final staff = hashPin(defaultStaffPin);
    final manager = hashPin(defaultManagerPin);
    final supervisor = hashPin(defaultSupervisorPin);
    batch.insert('app_users', {
      'role': 'staff',
      'pin_hash': staff.hash,
      'pin_salt': staff.salt,
    });
    batch.insert('app_users', {
      'role': 'manager',
      'pin_hash': manager.hash,
      'pin_salt': manager.salt,
    });
    batch.insert('app_users', {
      'role': 'supervisor',
      'pin_hash': supervisor.hash,
      'pin_salt': supervisor.salt,
    });

    await batch.commit(noResult: true);
  }

  Future<void> close() => _db.close();

  /// Runs [action] in a transaction, translating sqflite failures into
  /// [StorageException] so callers get one error type to handle.
  Future<T> transaction<T>(
    Future<T> Function(Transaction txn) action, {
    required String failureMessage,
  }) async {
    try {
      return await _db.transaction(action);
    } on AppException {
      rethrow; // Domain errors thrown inside the transaction pass through.
    } on DatabaseException catch (error) {
      throw StorageException(failureMessage, cause: error);
    }
  }
}

/// A PIN hash and the salt it was computed with.
class PinDigest {
  const PinDigest(this.hash, this.salt);

  final String hash;
  final String salt;
}

final Random _saltRandom = Random.secure();

/// Salted SHA-256 of [pin].
///
/// This is not a slow KDF — a 4-digit PIN has only 10 000 possibilities, so no
/// hashing scheme makes it brute-force resistant against someone holding the
/// database file. The salt is here to stop a stolen file from revealing that
/// two roles share a PIN, and to keep the clear text off disk.
PinDigest hashPin(String pin, {String? salt}) {
  final effectiveSalt = salt ??
      base64Url.encode(List<int>.generate(16, (_) => _saltRandom.nextInt(256)));
  final digest = sha256.convert(utf8.encode('$effectiveSalt:$pin'));
  return PinDigest(digest.toString(), effectiveSalt);
}
