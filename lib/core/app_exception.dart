/// Failure types surfaced to the UI.
///
/// Repositories catch raw `DatabaseException`s and rethrow these, so widgets
/// never have to know sqflite exists and can always show a sentence a shop
/// employee can act on.
library;

/// Base class for errors this app knows how to explain to a user.
sealed class AppException implements Exception {
  const AppException(this.message, {this.cause});

  /// A complete sentence, safe to show on screen.
  final String message;

  /// The underlying error, kept for logging. Never shown to the user.
  final Object? cause;

  @override
  String toString() => '$runtimeType: $message${cause == null ? '' : ' ($cause)'}';
}

/// A database read or write failed.
class StorageException extends AppException {
  const StorageException(super.message, {super.cause});
}

/// The caller supplied something the domain rejects — an empty product name, a
/// zero quantity, a duplicate payment method.
class ValidationException extends AppException {
  const ValidationException(super.message, {super.cause});
}

/// The requested row does not exist (or was filtered out as inactive).
class NotFoundException extends AppException {
  const NotFoundException(super.message, {super.cause});
}

/// The operation is not allowed in the current state, e.g. voiding an order
/// that is already voided.
class ConflictException extends AppException {
  const ConflictException(super.message, {super.cause});
}
