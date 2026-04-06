import 'package:bloc_error_control/bloc_error_control.dart';

/// Exception thrown when a cancelled token is checked.
///
/// This exception is thrown by [ICancelToken.throwIfCancelled] when the token
/// has been cancelled. It allows graceful interruption of long-running
/// operations without crashing the application.
///
/// Example:
/// ```dart
/// Future<void> heavyComputation(ICancelToken token) async {
///   for (var i = 0; i < 1000000; i++) {
///     token.throwIfCancelled(); // Throws BlocCanceledException if cancelled
///     // ... computation ...
///   }
/// }
/// ```
class BlocCanceledException implements Exception {
  /// The reason for cancellation (e.g., [CancelRequestReasons.manual]).
  final dynamic reason;

  /// Creates a cancellation exception with an optional reason.
  ///
  /// Defaults to [CancelRequestReasons.manual] if no reason is provided.
  BlocCanceledException([this.reason = CancelRequestReasons.manual]);

  @override
  String toString() => 'BlocCanceledException: ${reason ?? "No reason provided"}';
}
