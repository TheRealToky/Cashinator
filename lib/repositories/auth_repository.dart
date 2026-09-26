import 'package:sqflite/sqflite.dart';

import '../core/app_exception.dart';
import '../data/db/app_database.dart';

/// Who is using the tablet.
///
/// There are no per-person user accounts — the shop has a counter and an
/// office, not a staff directory. Instead there are three fixed roles, each
/// with its own PIN:
///
/// * [staff] runs the till (front office).
/// * [manager] owns the back office and can do everything in it.
/// * [supervisor] is a limited back-office login: it can browse order history,
///   void orders, record expenses and run the Excel exports, but not touch the
///   catalogue, payment methods or any PIN. It exists so a shift lead can
///   correct sales without holding the keys to prices and access.
enum UserRole {
  staff('staff'),
  manager('manager'),
  supervisor('supervisor');

  const UserRole(this.wireName);

  final String wireName;

  String get label => switch (this) {
        UserRole.staff => 'Front office',
        UserRole.manager => 'Back office',
        UserRole.supervisor => 'Supervisor',
      };

  /// Whether this role lands in the back office instead of the till.
  bool get isBackOffice =>
      this == UserRole.manager || this == UserRole.supervisor;

  /// Browse the order history and void orders.
  bool get canManageOrders => isBackOffice;

  /// Generate the Excel sales export.
  bool get canExport => isBackOffice;

  /// Open the Sample screen — a read-only slice of a day's order history, so
  /// anyone who may browse orders at all may sample them.
  bool get canViewSample => canManageOrders;

  /// Record and void expenses.
  ///
  /// Tied to [canManageOrders] rather than to the manager alone: an expense is
  /// the same kind of record as a sale, and a shift lead who is trusted to
  /// void a sale is trusted to write down the milk they bought. It stays out
  /// of the front office — the till is for customers, and money going out is
  /// the office's business.
  bool get canManageExpenses => canManageOrders;

  /// Record what the kitchen produced.
  ///
  /// Same access as expenses: a supervisor who reconciles the till can also
  /// note what was baked that day.
  bool get canRecordProduction => isBackOffice;

  /// Browse daily production logs.
  bool get canViewProductionHistory => isBackOffice;

  /// Record end-of-day unsold products.
  bool get canRecordUnsold => isBackOffice;

  /// Browse daily unsold logs.
  bool get canViewUnsoldHistory => isBackOffice;

  /// Add, edit and deactivate products.
  bool get canManageProducts => this == UserRole.manager;

  /// Add, edit and deactivate payment methods.
  bool get canManagePaymentMethods => this == UserRole.manager;

  /// Set the PIN for any role.
  bool get canChangePins => this == UserRole.manager;

  static UserRole? fromWire(String? value) => switch (value) {
        'staff' => UserRole.staff,
        'manager' => UserRole.manager,
        'supervisor' => UserRole.supervisor,
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
      UserRole.supervisor => AppDatabase.defaultSupervisorPin,
    };
    return await authenticate(defaultPin) == role;
  }
}
