import 'dart:async';

import 'package:bloc_error_control/src/exceptions/bloc_canceled_exception.dart';
import 'package:bloc_error_control/src/interfaces/i_cancel_token.dart';
import 'package:bloc_error_control/src/models/cancel_request_reasons.dart';
import 'package:bloc_error_control/src/models/event_cancel_token.dart';
import 'package:bloc_error_control/src/models/event_timeout_error.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:meta/meta.dart';

/// Signature for custom error logging functions.
///
/// Used with [BlocErrorControlMixin.logger] to provide custom error logging
/// (e.g., to Sentry, Firebase, or local analytics).
typedef ErrorLogger =
    void Function({
      required String tag,
      required Object error,
      required StackTrace stackTrace,
      required Object event,
    });

/// **BlocErrorControlMixin** — A powerful engine for automated error handling
/// and resource management in BLoC.
///
/// This mixin eliminates boilerplate `try-catch` blocks from event handlers
/// while providing automatic request cancellation, centralized error mapping,
/// and comprehensive logging.
///
/// ## Core Mechanism: Contextual Zones
///
/// The mixin leverages Dart's [Zone] API to propagate metadata through the
/// asynchronous call stack. When an event is dispatched, a protected zone is
/// created with the following data stored in `zoneValues`:
/// * `_eventKey` — The current event object [E]
/// * `_tokenKey` — A unique [ICancelToken] for this invocation
///
/// This allows the standard [onError] method to "see" the event and local
/// mappers, which are normally unavailable at this point in the BLoC lifecycle.
///
/// ## Lifecycle and CancelToken
///
/// The mixin implements **automatic resource cancellation**:
/// * A new [ICancelToken] is generated for each [EventHandler] call
/// * The [contextToken] getter returns the current zone's token — **always
///   pass it to async operations** (Dio, repositories, etc.)
/// * **Auto-cancellation:** The token is automatically cancelled when:
///   1. The event completes or is cancelled (e.g., via `restartable`)
///   2. An exception occurs inside the event
///   3. The BLoC is closed via [close] (prevents "zombie requests")
///
/// ## Error Flow Hierarchy & Priorities
///
/// When an error occurs, the following chain executes:
/// 1. **Silence Filter ([isGlobalSilent])** — If `true` (e.g., Dio cancellation),
///    the error is ignored.
/// 2. **Recursion Guard** — The `_isHandlingErrorKey` flag prevents infinite
///    loops if an error occurs during mapping or [emit].
/// 3. **Local Mapper** — The `mapError` passed to [on] is called first.
///    Has the highest priority.
/// 4. **Generated Mapper** — If code generation is used, the event-specific
///    mapper is called next.
/// 5. **Global Mapper ([mapErrorToState])** — Called if all previous mappers
///    returned `null`.
/// 6. **Reporting Filter** — If an error is successfully transformed into a
///    state, it's marked with `_errorReportedKey`. This prevents duplicate
///    logs in [BlocObserver] or Sentry, as [onError] will skip `super.onError`
///    for marked errors.
///
/// ## Technical Implementation Details
///
/// * **`sync: true`** — Used for immediate `LoadingState` delivery to the UI,
///   bypassing the microtask queue.
/// * **`Stream<T>.takeUntil`** — Each event's stream is forcibly limited by
///   the cancellation token's lifecycle, ensuring clean [emit] after
///   interruption.
/// * **Type Safety** — Internal casts via `Function?` and `as S?` work around
///   Dart's generic invariance constraints, allowing correct operation with
///   `ErrorStateMapper<T, S>`.
///
/// ## Usage Example
///
/// ```dart
/// class UserBloc extends Bloc<UserEvent, UserState>
///     with BlocErrorControlMixin<UserEvent, UserState> {
///
///   UserBloc() {
///     on<LoadUser>(_onLoadUser);
///   }
///
///   Future<void> _onLoadUser(LoadUser event, Emitter<UserState> emit) async {
///     emit(LoadingState());
///     final data = await repository.getUser(event.id, token: contextToken);
///     emit(LoadedState(data));
///   }
///
///   @override
///   UserState? mapErrorToState(Object error, StackTrace s, UserEvent event) {
///     if (error is SocketException) return ErrorState('No internet');
///     return ErrorState('Something went wrong');
///   }
/// }
/// ```
///
/// ## Internal Architecture Diagram
///
/// ```
/// ┌───────────────────────────────────────────────────────────
/// │                     BLOC
/// │
/// │  ┌─────────────┐
/// │  │ Event 1     │
/// │  │ Zone 1      │ ──► [Token 1] ──► [_activeTokens]
/// │  │ Controller1 │ ──► [States] ───► Output stream
/// │  └─────────────┘
/// │
/// │  ┌─────────────┐
/// │  │ Event 2     │
/// │  │ Zone 2      │ ──► [Token 2] ──► [_activeTokens]
/// │  │ Controller2 │ ──► [States] ───► Output stream
/// │  └─────────────┘
/// │
/// │  ┌─────────────┐
/// │  │ Event 3     │
/// │  │ Zone 3      │ ──► [Token 3] ──► [_activeTokens]
/// │  │ Controller3 │ ──► [States] ───► Output stream
/// │  └─────────────┘
/// └───────────────────────────────────────────────────────────
/// ```
// {{REG_BEGIN}}
mixin BlocErrorControlMixin<E extends Object, S> on Bloc<E, S> {
  static const _eventKey = #app_bloc_handler_event;
  static const _tokenKey = #app_bloc_cancel_token;
  static const _isHandlingErrorKey = #app_bloc_is_handling_error;
  static const _errorReportedKey = #app_bloc_error_reported;

  ErrorLogger? _logger;

  /// Getter for the error logger.
  ///
  /// Returns a default logger that prints to the console using [debugPrint].
  /// Override by calling [logger].
  @protected
  ErrorLogger get logger =>
      _logger ??
      ({
        required String tag,
        required Object error,
        required StackTrace stackTrace,
        required Object event,
      }) => debugPrint("[$tag] '${event.runtimeType}'\nError: $error\nStackTrace: $stackTrace");

  /// Setter for the error logger.
  ///
  /// Allows passing a custom logger (e.g., in the Bloc constructor).
  @protected
  @visibleForTesting
  set logger(ErrorLogger value) => _logger = value;

  final _activeTokens = <EventCancelToken<E>>{};

  /// Determines which errors should be silently ignored.
  ///
  /// Override this method to filter out specific errors that shouldn't
  /// trigger state changes or logging. By default, ignores:
  /// - [BlocCanceledException] (internal cancellation)
  /// - Any error that occurs after the token has been cancelled
  @protected
  bool isGlobalSilent(Object e, StackTrace s) {
    // Ignore internal cancellation exceptions from throwIfCancelled
    if (e is BlocCanceledException) {
      return true;
    }

    // Ignore any error if the current zone's token is already cancelled
    // (covers DioException.cancel, http.ClientException, etc.)
    try {
      return contextToken.isCancelled;
    } on Object catch (_) {
      return false;
    }
  }

  /// **Global error mapper.**
  ///
  /// Must be implemented in your Bloc. Define common error-to-state conversion
  /// logic here, e.g., transforming `SocketException` into an offline state.
  ///
  /// This method is called when no local or generated mapper handles the error.
  @protected
  @mustBeOverridden
  @mustCallSuper
  S? mapErrorToState(Object error, StackTrace s, E event);

  // Cached token for out-of-zone calls
  EventCancelToken<E>? _fallbackToken;

  /// Returns the [ICancelToken] for the currently executing event.
  ///
  /// **Always pass this token to async operations:**
  /// `repo.getData(token: contextToken)`
  ///
  /// The token is automatically cancelled when:
  /// - The event handler completes
  /// - An exception occurs
  /// - A new event of the same type is dispatched (with `restartable`)
  /// - The BLoC is closed
  @protected
  @visibleForTesting
  ICancelToken get contextToken {
    final token = Zone.current[_tokenKey];
    if (token is ICancelToken) {
      return token;
    }

    // In debug mode, fail immediately
    assert(() {
      throw StateError('contextToken accessed outside event handler');
    }(), 'contextToken accessed outside event handler');

    // In release mode, create a fallback
    _fallbackToken ??= EventCancelToken<E>.fallback('contextToken.fallback');
    return _fallbackToken!;
  }

  // {{MAPPER_REPLACE}}
  /// A tag used for logging to identify the source Bloc.
  ///
  /// Override this getter to provide a meaningful name for your Bloc.
  @protected
  String get tag;

  /// Returns an event-specific error mapper (used by code generation).
  ///
  /// This method is automatically overridden when using code generation
  /// with `@BlocErrorControl` and `@ErrorStateFor` annotations.
  @protected
  S? getErrorMapperForEvent(Object error, StackTrace s, E event) => null;

  // {{MAPPER_REPLACE}}

  @override
  void on<T extends E>(
    EventHandler<T, S> handler, {
    EventTransformer<T>? transformer,
    Duration timeout = const Duration(seconds: 30),
  }) => super.on<T>(
    handler,
    transformer: _errorTransformerZone(base: transformer, eventTimeout: timeout),
  );

  @override
  @mustCallSuper
  void onError(Object error, StackTrace stackTrace) {
    // Check for silent errors BEFORE the zone
    if (isGlobalSilent(error, stackTrace)) {
      return;
    }

    _onErrorZone(error, stackTrace);

    // If the error was already handled in the zone, don't bubble to super
    final reportedError = Zone.current[_errorReportedKey];
    if (identical(reportedError, error)) {
      return;
    }

    super.onError(error, stackTrace);
  }

  /// Creates a protected zone around the event stream.
  ///
  /// Each event runs in its own zone with isolated cancellation tokens
  /// and error handling.
  ///
  /// ```
  /// INPUT EVENT STREAM:
  /// (Event1)────(Event2)────(Event3)────►
  ///
  /// TRANSFORMER creates for EACH event:
  /// │
  /// ├── Event1:
  /// │   ├── Zone1
  /// │   ├── Token1
  /// │   ├── Controller1
  /// │   └── Handler executes
  /// │        └── [State1, State2, State3]──► (to output)
  /// │
  /// ├── Event2:
  /// │   ├── Zone2
  /// │   ├── Token2
  /// │   ├── Controller2
  /// │   └── WAITS for Event1 to finish
  /// │        (due to rootTransformer)
  /// │
  /// └── Event3: waits for Event2
  /// ```
  EventTransformer<T> _errorTransformerZone<T extends E>({
    EventTransformer<T>? base,
    Duration eventTimeout = const Duration(seconds: 30),
  }) => (events, mapper) {
    final rootTransformer =
        base ??
        (Stream<T> es, EventMapper<T> m) =>
            Bloc.transformer(es, (event) => m(event as T)).cast<T>();

    return rootTransformer(events, (T event) {
      final token = EventCancelToken<E>(event: event);

      _activeTokens.add(token);

      // Using Object to Avoid TypeError at Runtime
      final controller = StreamController<Object?>(
        sync: true,
        onCancel: () {
          _removeToken(token);
          if (!token.isCancelled) {
            token.cancel(CancelRequestReasons.manual);
          }
        },
      );

      runZonedGuarded(
        () async {
          try {
            final stream = (mapper(event) as Stream<dynamic>)
                .takeUntil(token.whenCancel.asStream())
                .timeout(
                  eventTimeout,
                  onTimeout: (sink) {
                    sink
                      ..addError(EventTimeoutError<T>(event: event, message: 'Event timeout'))
                      ..close();
                  },
                );

            await for (final res in stream) {
              try {
                if (!controller.isClosed) {
                  controller.add(res);
                }
              } on Object catch (e, s) {
                if (e is StateError && e.message.contains('closed')) {
                  break;
                }
                _onErrorZone(e, s);
              }
            }
          } on Object catch (e, s) {
            _onErrorZone(e, s);
          } finally {
            _removeToken(token);
            try {
              if (!controller.isClosed) {
                await controller.close();
              }
            } on Object catch (e, s) {
              _onErrorZone(e, s);
            }
          }
        },
        _onErrorZone,
        zoneValues: {_eventKey: event, _tokenKey: token, _isHandlingErrorKey: false},
      );

      // cast<T> is needed to match the signature of EventTransformer in Bloc
      return controller.stream.cast<T>();
    });
  };

  /// Core error processing logic extracted from standard [onError].
  void _onErrorZone(Object error, StackTrace stackTrace) {
    if (isGlobalSilent(error, stackTrace)) {
      return;
    }

    final event = Zone.current[_eventKey] as E?;
    final isAlreadyHandling = Zone.current[_isHandlingErrorKey] == true;

    if (event != null && !isAlreadyHandling) {
      try {
        final errorState =
            getErrorMapperForEvent(error, stackTrace, event) ??
            mapErrorToState(error, stackTrace, event);

        // Log asynchronously to avoid blocking the event flow
        scheduleMicrotask(() {
          try {
            logger(error: error, stackTrace: stackTrace, tag: tag, event: event);
          } on Object catch (e, s) {
            debugPrint('Failed to log error: $e\nTrace: $s');
          }
        });

        final eState = errorState;
        if (eState is S && !isClosed) {
          // Emit in a separate zone with a flag to prevent infinite loops
          runZoned(
            // ignore: invalid_use_of_visible_for_testing_member
            () => emit(eState),
            zoneValues: {
              _isHandlingErrorKey: true,
              _errorReportedKey: error,
            },
          );
        }
      } on Object catch (e, s) {
        // If state mapping fails, fall back to base onError
        super.onError(e, s);
      }
    }
  }

  /// Cancels all tokens associated with events of a specific type.
  @protected
  @visibleForTesting
  void cancelTokensByEventType<T extends E>() {
    final tokens = [..._activeTokens];

    for (final token in tokens) {
      if (token.event is T && !token.isCancelled) {
        _removeToken(token);
      }
    }
  }

  /// Cancels the token for a specific event instance.
  @protected
  @visibleForTesting
  bool cancelTokenForEvent(E event) {
    final tokens = [..._activeTokens];

    for (final token in tokens) {
      if (identical(token.event, event) && !token.isCancelled) {
        _removeToken(token);
        return true;
      }
    }

    return false;
  }

  /// Returns diagnostic information about active tokens.
  ///
  /// Useful for debugging hanging requests or monitoring resource usage.
  @protected
  @visibleForTesting
  List<Map<String, dynamic>> getActiveTokensInfo() {
    final tokens = [..._activeTokens];

    return tokens
        .map(
          (token) => {
            'eventType': token.operationName,
            'eventHash': token.hash,
            'startTime': token.startTime,
            'ageMs': DateTime.now().difference(token.startTime).inMilliseconds,
            'isCancelled': token.isCancelled,
            'duration': token.duration,
          },
        )
        .toList();
  }

  /// Checks whether an active token exists for the given event.
  @protected
  @visibleForTesting
  bool hasActiveTokenForEvent(E event) {
    final tokens = [..._activeTokens];

    return tokens.any((token) => identical(token.event, event) && !token.isCancelled);
  }

  void _removeToken(EventCancelToken<E> token) {
    final tokens = [..._activeTokens];

    if (tokens.contains(token)) {
      if (!token.isCancelled) {
        token.cancel(CancelRequestReasons.manual);
      }
      _activeTokens.remove(token);
    }
  }

  @override
  @mustCallSuper
  Future<void> close() {
    final tokens = [..._activeTokens];

    for (final token in tokens) {
      if (!token.isCancelled) {
        _removeToken(token);
      }
    }
    _activeTokens.clear();

    return super.close();
  }
}

/// Pure Dart implementation of `takeUntil` (no rxdart dependency).
///
/// Closes the main stream as soon as the other-stream emits any value.
extension _StreamTakeUntil<T> on Stream<T> {
  Stream<T> takeUntil(Stream<Object?> other) {
    final controller = StreamController<T>(sync: true);
    StreamSubscription<T>? mainSubscription;
    StreamSubscription<Object?>? otherSubscription;

    controller
      ..onListen = () {
        mainSubscription = listen(
          controller.add,
          onError: controller.addError,
          onDone: controller.close,
        );

        otherSubscription = other.listen(
          (_) {
            mainSubscription?.cancel();
            otherSubscription?.cancel();
            controller.close();
          },
          onError: controller.addError,
          onDone: () {
            // If the signal stream closes itself, do nothing;
            // continue listening to the main stream.
          },
          cancelOnError: true,
        );
      }
      ..onCancel = () async {
        await mainSubscription?.cancel();
        await otherSubscription?.cancel();
      };

    return controller.stream;
  }
}

// {{REG_END}}
