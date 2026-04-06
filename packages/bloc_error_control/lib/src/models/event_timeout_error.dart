import 'package:bloc_error_control/src/mixins/bloc_error_control_mixin.dart';

/// Error thrown when an event handler exceeds its timeout limit.
///
/// This error is automatically thrown by [BlocErrorControlMixin] when an event
/// handler takes longer than the specified timeout - duration (default 30 seconds).
/// The error is then processed through the mixin's error handling pipeline.
///
/// Type parameter [E] represents the event type that timed out.
///
/// Example:
/// ```dart
/// on<LongRunningEvent>(
///   (event, emit) async {
///     // If this takes more than 5 seconds, EventTimeoutError is thrown
///     await verySlowOperation();
///   },
///   timeout: Duration(seconds: 5),
/// );
///
/// @override
/// State? mapErrorToState(Object error, StackTrace stack, Event event) {
///   if (error is EventTimeoutError) {
///     return ErrorState('Operation timed out');
///   }
///   return null;
/// }
/// ```
class EventTimeoutError<E> extends Error {
  /// The event that caused the timeout, if available.
  final E? event;

  /// A human-readable description of the timeout.
  final String message;

  /// Creates a timeout error for the given event.
  EventTimeoutError({required this.event, required this.message});
}
