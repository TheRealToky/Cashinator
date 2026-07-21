import 'package:sqflite/sqflite.dart';

import '../core/app_exception.dart';
import '../data/db/app_database.dart';

/// Who is using the tablet.
///
/// There are exactly two roles and no user accounts — the shop has a counter
/// and an office, not a staff directory.
enum UserRole {
  staff('staff'),
  manager('manager');

  const UserRole(this.wireName);

  final String wireName;

  String get label => switch (this) {
        UserRole.staff => 'Front office',
        UserRole.manager => 'Back office',
      };

  static UserRole? fromWire(String? value) => switch (value) {
        'staff' => UserRole.staff,
        'manager' => UserRole.manager,
        _ => null,
      };
}

/// PIN checking and PIN changes.
class AuthRepository {
  AuthRepository(this._database);

  final AppDatabase _database;

  Database get _db => _database.db;

  /// Returns the role whose PIN matches [pin], or `null` if none does.
  ///
  /// Both roles are checked so a single keypad can route the user: type the
  /// front-office PIN and land on the till, type the manager PIN and land in
  /// the back office.
  Future<UserRole?> authenticate(String pin) async {
    final trimmed = pin.trim();
    if (trimmed.isEmpty) return null;

    try {
      final rows = await _db.query('app_users');
      for (final row in rows) {
        final salt = row['pin_salt'] as String?;
        final expected = row['pin_hash'] as String?;
        if (salt == null || expected == null) continue;

        if (hashPin(trimmed, salt: salt).hash == expected) {
          return UserRole.fromWire(row['role'] as String?);
        }
      }
      return null;
    } on DatabaseException catch (error) {
      throw StorageException('Could not verify the PIN.', cause: error);
    }
  }

  /// Replaces the PIN for [role].
  ///
  /// Refuses a PIN already in use by the other role — otherwise front-office
  /// staff would silently gain back-office access.
  Future<void> changePin({
    required UserRole role,
    required String newPin,
  }) async {
    final trimmed = newPin.trim();

    if (trimmed.length < 4 || trimmed.length > 8) {
      throw const ValidationException('The PIN must be 4 to 8 digits.');
    }
    if (!RegExp(r'^\d+$').hasMatch(trimmed)) {
      throw const ValidationException('The PIN must contain digits only.');
    }

    final owner = await authenticate(trimmed);
    if (owner != null && owner != role) {
      throw const ConflictException(
        'That PIN is already used by the other role. Choose a different one.',
      );
    }

    final digest = hashPin(trimmed);
    try {
      final affected = await _db.update(
        'app_users',
        {'pin_hash': digest.hash, 'pin_salt': digest.salt},
        where: 'role = ?',
        whereArgs: [role.wireName],
      );
      if (affected == 0) {
        throw const NotFoundException('That role does not exist.');
      }
    } on DatabaseException catch (error) {
      throw StorageException('Could not save the new PIN.', cause: error);
    }
  }

  /// True while a role still uses the PIN shipped with the app.
  ///
  /// The back office shows a warning banner until both are changed.
  Future<bool> isUsingDefaultPin(UserRole role) async {
    final defaultPin = switch (role) {
      UserRole.staff => AppDatabase.defaultStaffPin,
      UserRole.manager => AppDatabase.defaultManagerPin,
    };
    return await authenticate(defaultPin) == role;
  }
}
