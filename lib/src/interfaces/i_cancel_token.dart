import 'dart:async';

import 'package:bloc_error_control/src/exceptions/bloc_canceled_exception.dart';
import 'package:bloc_error_control/src/models/event_cancel_token.dart';

/// Universal interface for cancellation operations.
///
/// Allows the mixin to manage event lifecycle without knowing about specific
/// HTTP clients (Dio, http, etc.). This abstraction enables cancellation
/// support for any asynchronous operation.
///
/// Implement this interface to integrate custom cancellation logic or use
/// the built-in [EventCancelToken] implementation.
///
/// Example usage in a repository:
/// ```dart
/// class UserRepository {
///   Future<String> getUser(int id, ICancelToken? token) async {
///     token?.throwIfCancelled(); // Check before starting
///
///     final response = await dio.get('/user/$id', cancelToken: token);
///     token?.throwIfCancelled(); // Check after response
///
///     return response.data;
///   }
/// }
/// ```
abstract interface class ICancelToken {
  /// Whether this token has been cancelled.
  ///
  /// Returns `true` if [cancel] was called, `false` otherwise.
  bool get isCancelled;

  /// A future that completes when the token is cancelled.
  ///
  /// Useful for awaiting cancellation in async operations:
  /// ```dart
  /// await Future.any([
  ///   longRunningOperation(),
  ///   token.whenCancel,
  /// ]);
  /// ```
  Future<void> get whenCancel;

  /// Manually cancels this token.
  ///
  /// Called automatically by the mixin when:
  /// - An event handler completes
  /// - An exception occurs
  /// - A new event of the same type is dispatched
  /// - The BLoC is closed
  ///
  /// Optionally accepts a [reason] for debugging purposes.
  void cancel([dynamic reason]);

  /// Throws [BlocCanceledException] if this token has been cancelled.
  ///
  /// Use this to interrupt long-running operations with minimal boilerplate:
  /// ```dart
  /// for (var i = 0; i < items.length; i++) {
  ///   token.throwIfCancelled(); // Stops iteration if cancelled
  ///   process(items[i]);
  /// }
  /// ```
  void throwIfCancelled();
}
