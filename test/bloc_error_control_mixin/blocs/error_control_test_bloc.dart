import 'dart:async';

import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:bloc_error_control/src/interfaces/i_cancel_token.dart';
import 'package:bloc_error_control/src/mixins/bloc_error_control_mixin.dart';
import 'package:bloc_error_control/src/models/event_cancel_token.dart';
import 'package:dio/dio.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

abstract class TestState {}

class InitialState extends TestState {}

class LoadingState extends TestState {}

class DataState extends TestState {
  final dynamic data;

  DataState(this.data);
}

class ErrorState extends TestState {}

class LocalErrorState extends TestState {
  final String message;

  LocalErrorState(this.message);
}

abstract class TestEvent {}

class SuccessEvent extends TestEvent {}

class ErrorEvent extends TestEvent {}

class SilentErrorEvent extends TestEvent {}

class CancelableEvent extends TestEvent {}

class SequentialEvent extends TestEvent {
  final int id;

  SequentialEvent(this.id);
}

class RestartableEvent extends TestEvent {
  final int id;

  RestartableEvent(this.id);
}

class DebounceEvent extends TestEvent {
  final int id;

  DebounceEvent(this.id);
}

class InfiniteStreamEvent extends TestEvent {}

class LocalErrorEvent extends TestEvent {
  final bool returnNull;

  LocalErrorEvent({this.returnNull = false});
}

class UnknownEvent extends TestEvent {}

class TokenTestEvent extends TestEvent {
  final int id;

  TokenTestEvent(this.id);
}

class CustomSequentialEvent extends TestEvent {
  final int id;

  CustomSequentialEvent(this.id);
}

abstract class RecoveryEvent extends TestEvent {}

class RecoveryErrorEvent extends RecoveryEvent {}

class RecoverySuccessEvent extends RecoveryEvent {}

class ZombieSuccessEvent extends RecoveryEvent {}

class RaceConditionSuccessEvent extends RecoveryEvent {}

class ConcurrentEvent extends TestEvent with EquatableMixin {
  final int id;

  final Duration delay;

  ConcurrentEvent(this.id, {this.delay = const Duration(milliseconds: 50)});

  @override
  List<Object?> get props => [id, delay];
}

/// Test BLoC for validating [BlocErrorControlMixin] functionality.
///
/// This bloc is designed to test various error handling scenarios including:
/// - Success events
/// - Silent errors (cancellation)
/// - Sequential event processing
/// - Local vs global error mappers
/// - Zone isolation
/// - Token cancellation
///
/// ## Events
/// - [SuccessEvent]: Normal successful event that emits states
/// - [SilentErrorEvent]: Triggers a cancellation error that should be silently ignored
/// - [SequentialEvent]: Processes events in sequence using `sequential()` transformer
/// - [LocalErrorEvent]: Tests local error mapper priority over global mapper
/// - [UnknownEvent]: Tests error ignoring via returning `null` from mapper
///
/// ## States
/// - [InitialState]: Initial bloc state
/// - [LoadingState]: Emitted when async operation starts
/// - [DataState]: Emitted on successful completion with data
/// - [ErrorState]: Emitted for unhandled errors (global mapper)
/// - [LocalErrorState]: Emitted for errors handled by local mapper
///
/// ## Error Mapper Hierarchy
/// 1. **Local mapper**: [getErrorMapperForEvent] handles [LocalErrorEvent]
/// 2. **Global mapper**: [mapErrorToState] handles all other events
/// 3. **Silent filter**: [isGlobalSilent] ignores cancellation errors
///
/// ## Usage in Tests
/// ```dart
/// final bloc = ErrorHandlerTestBloc();
///
/// // Test successful event
/// bloc.add(SuccessEvent());
/// await expectLater(bloc.stream, emitsInOrder([LoadingState(), DataState('Success')]));
///
/// // Test error handling
/// bloc.add(ErrorEvent());
/// await expectLater(bloc.stream, emits(ErrorState()));
/// ```
class ErrorHandlerTestBloc extends Bloc<TestEvent, TestState>
    with BlocErrorControlMixin<TestEvent, TestState> {
  @override
  String get tag => 'ErrorHandlerTestBloc';

  @override
  TestState? mapErrorToState(Object error, StackTrace s, TestEvent event) {
    // [UnknownEvent] errors are ignored (return null)
    if (event is UnknownEvent) {
      return null;
    }
    return ErrorState();
  }

  @override
  TestState? getErrorMapperForEvent(Object error, StackTrace s, TestEvent event) {
    // Local mapper has priority over global mapper
    if (event is LocalErrorEvent) {
      return LocalErrorState('local error');
    }

    return null;
  }

  ErrorHandlerTestBloc() : super(InitialState()) {
    /// Handles normal successful events.
    ///
    /// Emits: [LoadingState] → [DataState] with 'Success' after 10ms delay.
    on<SuccessEvent>(
      (event, emit) async {
        emit(LoadingState());
        await Future.delayed(const Duration(milliseconds: 10));
        emit(DataState('Success'));
      },
    );

    /// Handles silent cancellation errors.
    ///
    /// Cancels the token and throws [DioExceptionType.cancel] which is
    /// filtered by [isGlobalSilent] and should not emit any error state.
    on<SilentErrorEvent>((event, emit) async {
      contextToken.cancel();
      throw DioException(
        requestOptions: RequestOptions(),
        type: DioExceptionType.cancel,
      );
    });

    /// Handles sequential events.
    ///
    /// Uses `sequential()` transformer to ensure events are processed
    /// one after another, maintaining order.
    ///
    /// Emits: [LoadingState] → [DataState] with event id after 50ms delay.
    on<SequentialEvent>((event, emit) async {
      emit(LoadingState());
      await Future.delayed(const Duration(milliseconds: 50));
      emit(DataState(event.id));
    }, transformer: sequential());
  }
}



// Создаём специальный блок для этого теста
class FailingMapperBloc extends Bloc<TestEvent, TestState>
    with BlocErrorControlMixin<TestEvent, TestState> {
  FailingMapperBloc() : super(InitialState()) {
    on<ErrorEvent>((event, emit) async {
      emit(LoadingState());
      throw Exception('Original error');
    });
  }

  @override
  String get tag => 'FailingMapperBloc';

  @override
  TestState? mapErrorToState(Object error, StackTrace stack, TestEvent event) {
    // Этот маппер выбрасывает исключение!
    throw Exception('Mapper failed!');
  }
}

extension DioCancelTokenX on ICancelToken {
  /// Converts [ICancelToken] to Dio's [CancelToken].
  ///
  /// Automatically synchronizes the cancellation state and propagates the
  /// cancellation reason when available.
  ///
  /// This extension is useful when you need to pass the mixin's cancellation
  /// token to Dio HTTP requests while maintaining automatic cancellation
  /// capabilities.
  ///
  /// Example:
  /// ```dart
  /// Future<void> _onFetchData(FetchDataEvent event, Emitter<AppState> emit) async {
  ///   emit(AppLoading());
  ///   final response = await dio.get(
  ///     'https://api.example.com/data',
  ///     cancelToken: contextToken.toDio(),
  ///   );
  ///   emit(AppLoaded(response.data));
  /// }
  /// ```
  CancelToken toDio() {
    final dioToken = CancelToken();

    // If already cancelled, return an already cancelled Dio token immediately
    if (isCancelled) {
      _safeCancel(dioToken);
      return dioToken;
    }

    // Listen for future cancellation and propagate to Dio token.
    // Using unawaited because we don't need to wait for this operation.
    unawaited(
      whenCancel
          .then((_) {
            _safeCancel(dioToken);
          })
          .catchError((_) {
            // Error ignored — token already cancelled or resources already disposed.
          }),
    );

    return dioToken;
  }

  /// Safely cancels the Dio token if it hasn't been cancelled already.
  ///
  /// Attempts to extract the cancellation reason from [EventCancelToken]
  /// and passes it to Dio for debugging purposes.
  void _safeCancel(CancelToken dioToken) {
    if (!dioToken.isCancelled) {
      // Try to get the cancellation reason from EventCancelToken implementation
      final dynamic reason = this is EventCancelToken ? (this as EventCancelToken).reason : null;
      dioToken.cancel(reason);
    }
  }
}
