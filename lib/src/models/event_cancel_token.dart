import 'dart:async';

import 'package:bloc_error_control/src/exceptions/bloc_canceled_exception.dart';
import 'package:bloc_error_control/src/interfaces/i_cancel_token.dart';
import 'package:bloc_error_control/src/mixins/bloc_error_control_mixin.dart';

/// An extended cancellation token tied to a specific event.
///
/// This token is automatically created for each event dispatched to a BLoC
/// that uses [BlocErrorControlMixin]. It provides event-specific cancellation
/// tracking, diagnostics, and lifecycle management.
///
/// Type parameter [E] represents the event type this token is associated with.
///
/// Example:
/// ```dart
/// final token = EventCancelToken(event: loadUserEvent);
/// print(token.operationName); // 'LoadUserEvent'
/// print(token.hash); // Unique hash for this event instance
/// ```
class EventCancelToken<E> implements ICancelToken {
  /// The event associated with this token, or `null` for fallback tokens.
  final E? event;

  /// The timestamp when this token was created.
  final DateTime startTime;

  /// Internal debug name for fallback tokens (when event is null).
  final String? _debugName;

  final _completer = Completer<void>();
  bool _isCancelled = false;
  dynamic _reason;

  /// Creates a token linked to a specific event.
  EventCancelToken({required this.event}) : startTime = DateTime.now(), _debugName = null;

  /// Creates a fallback token for use outside event handlers.
  ///
  /// Fallback tokens are used when [BlocErrorControlMixin.contextToken] is accessed outside
  /// an event handler context (e.g., in debug mode or during testing).
  EventCancelToken.fallback(this._debugName) : event = null, startTime = DateTime.now();

  @override
  bool get isCancelled => _isCancelled;

  @override
  Future<void> get whenCancel => _completer.future;

  /// The reason why this token was cancelled, if any.
  dynamic get reason => _reason;

  /// The name of the operation associated with this token.
  ///
  /// Returns the event type name for event-bound tokens, or the debug name
  /// for fallback tokens, or 'Unknown' as a last resort.
  String get operationName => event?.runtimeType.toString() ?? _debugName ?? 'Unknown';

  /// The duration this token has existed.
  Duration get duration => DateTime.now().difference(startTime);

  /// A unique hash for this token, based on the associated event or debug name.
  int get hash => event?.hashCode ?? _debugName.hashCode;

  @override
  void cancel([dynamic reason]) {
    if (_isCancelled) {
      return;
    }
    _isCancelled = true;
    _reason = reason;
    if (!_completer.isCompleted) {
      _completer.complete();
    }
  }

  @override
  void throwIfCancelled() {
    if (_isCancelled) {
      throw BlocCanceledException();
    }
  }
}
