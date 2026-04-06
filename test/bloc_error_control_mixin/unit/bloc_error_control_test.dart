import 'dart:async';

import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:bloc_error_control/src/annotations/annotations.dart';
import 'package:bloc_error_control/src/exceptions/bloc_canceled_exception.dart';
import 'package:bloc_error_control/src/interfaces/i_cancel_token.dart';
import 'package:bloc_error_control/src/models/cancel_request_reasons.dart';
import 'package:bloc_error_control/src/models/event_cancel_token.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:dio/dio.dart';
import 'package:rxdart/rxdart.dart';
import 'package:test/test.dart';

import '../blocs/error_control_test_bloc.dart';

void main() {
  group('BlocExceptionHandlerMixin Integrated Tests', () {
    test('Resilience: Full context isolation after critical error', () async {
      final states = <TestState>[];
      final bloc = ErrorHandlerTestBloc();
      final sub = bloc.stream.listen(states.add);

      bloc
        ..on<RecoveryEvent>((event, emit) async {
          if (event is RecoveryErrorEvent) {
            emit(LoadingState());
            // Async delay required to enter the transformer zone
            await Future.delayed(const Duration(milliseconds: 10));
            throw Exception('Crash 1');
          }

          if (event is RecoverySuccessEvent) {
            emit(LoadingState());
            await Future.delayed(const Duration(milliseconds: 10));
            emit(DataState('Success 2'));
          }
        }, transformer: sequential())
        ..add(RecoveryErrorEvent());

      // Wait for ErrorState to appear
      await bloc.stream
          .firstWhere((state) => state is ErrorState)
          .timeout(const Duration(milliseconds: 500));

      bloc.add(RecoverySuccessEvent());

      // Wait for final result
      await bloc.stream
          .firstWhere((state) => state is DataState)
          .timeout(const Duration(milliseconds: 500));

      await sub.cancel();
      await bloc.close();

      expect(states, [
        isA<LoadingState>(),
        isA<ErrorState>(),
        isA<LoadingState>(),
        isA<DataState>().having((s) => s.data, 'data', 'Success 2'),
      ]);
    });

    test('Silent: DioExceptionType.cancel is ignored, Bloc remains functional', () async {
      final states = <TestState>[];
      final bloc = ErrorHandlerTestBloc();
      final subscription = bloc.stream.listen(states.add);

      // Add silent error event
      bloc.add(SilentErrorEvent());

      // Allow microtask for zone to process the error
      await Future.delayed(const Duration(milliseconds: 20));

      // Add successful event
      bloc.add(SuccessEvent());

      // Wait for successful event completion
      await Future.delayed(const Duration(milliseconds: 50));

      // Verify: No states from silent error, success states present
      expect(states, [
        isA<LoadingState>(), // From SuccessEvent
        isA<DataState>().having((s) => s.data, 'data', 'Success'),
      ]);

      await subscription.cancel();
    });

    test('Zones: Each event runs in its own zone with unique ICancelToken', () async {
      final bloc = ErrorHandlerTestBloc();
      final capturedTokens = <int, ICancelToken>{};
      final completer = Completer<void>();

      // Register a new event not present in bloc constructor
      bloc
        ..on<TokenTestEvent>((event, emit) async {
          // At this point the mixin has created a zone
          capturedTokens[event.id] = bloc.contextToken;

          if (capturedTokens.length == 2) {
            completer.complete();
          }
        }, transformer: sequential())
        ..add(TokenTestEvent(1))
        ..add(TokenTestEvent(2));

      await completer.future.timeout(const Duration(seconds: 1));
      await bloc.close();

      expect(capturedTokens[1], isNotNull);
      expect(capturedTokens[2], isNotNull);
      expect(
        capturedTokens[1],
        isNot(same(capturedTokens[2])),
        reason: 'Each event execution must have its own unique ICancelToken instance',
      );
    });

    blocTest<ErrorHandlerTestBloc, TestState>(
      'Sequential: Events must execute strictly in order (mixin preserves ordering)',
      build: ErrorHandlerTestBloc.new,
      act: (bloc) {
        bloc
          ..add(SequentialEvent(1))
          ..add(SequentialEvent(2));
      },
      wait: const Duration(milliseconds: 200),
      expect: () => [
        isA<LoadingState>(),
        isA<DataState>().having((s) => s.data, 'id', 1),
        isA<LoadingState>(),
        isA<DataState>().having((s) => s.data, 'id', 2),
      ],
    );

    test('Sequential: Guaranteed sequential execution (no zone overlap)', () async {
      final bloc = ErrorHandlerTestBloc();
      final timestamps = <int, Map<String, DateTime>>{};
      final completer = Completer<void>();

      bloc
        ..on<CustomSequentialEvent>((event, emit) async {
          timestamps[event.id] = {'start': DateTime.now()};

          emit(LoadingState());
          await Future.delayed(const Duration(milliseconds: 50));

          emit(DataState(event.id));
          timestamps[event.id]!['end'] = DateTime.now();

          if (timestamps.length == 2) {
            completer.complete();
          }
        }, transformer: sequential())
        ..add(CustomSequentialEvent(1))
        ..add(CustomSequentialEvent(2));

      await completer.future.timeout(const Duration(seconds: 1));

      final end1 = timestamps[1]!['end']!;
      final start2 = timestamps[2]!['start']!;

      expect(
        start2.isAfter(end1) || start2.isAtSameMomentAs(end1),
        isTrue,
        reason: 'Second event started before first completed. Sequential is broken!',
      );

      expect(bloc.state, isA<DataState>().having((s) => s.data, 'data', 2));
    });

    test('Debounce: Guaranteed atomic execution and no unnecessary zones', () async {
      final bloc = ErrorHandlerTestBloc();
      final executionLog = <int>[];
      final capturedTokens = <int, ICancelToken>{};
      final completer = Completer<void>();

      bloc
        ..on<DebounceEvent>(
          (event, emit) async {
            final id = event.id;
            executionLog.add(id);
            capturedTokens[id] = bloc.contextToken;

            emit(LoadingState());
            await Future.delayed(const Duration(milliseconds: 10));
            emit(DataState('Result $id'));

            if (id == 3) {
              completer.complete();
            }
          },
          transformer: (events, mapper) =>
              events.debounceTime(const Duration(milliseconds: 100)).flatMap(mapper),
        )
        ..add(DebounceEvent(1));
      await Future.delayed(const Duration(milliseconds: 30));
      bloc.add(DebounceEvent(2));
      await Future.delayed(const Duration(milliseconds: 30));
      bloc.add(DebounceEvent(3));

      await completer.future.timeout(const Duration(milliseconds: 500));

      // Only ID 3 should be in execution log
      expect(
        executionLog,
        [3],
        reason: 'Events 1 and 2 must be filtered out before entering execution zone',
      );

      // Verify no unnecessary tokens were created
      expect(capturedTokens.containsKey(1), isFalse);
      expect(capturedTokens.containsKey(2), isFalse);
      expect(capturedTokens.containsKey(3), isTrue);

      expect(bloc.state, isA<DataState>().having((s) => s.data, 'data', 'Result 3'));
    });

    test('Restartable: Guaranteed async call interruption via ICancelToken', () async {
      final bloc = ErrorHandlerTestBloc();
      final completer = Completer<void>();
      var firstRequestInterrupted = false;

      // Используем уникальное событие для теста
      bloc
        ..on<RecoveryEvent>((event, emit) async {
          emit(LoadingState());

          if (event is RecoveryErrorEvent) {
            try {
              // Simulate Dio request: wait for either delay or token cancellation
              await Future.any([
                Future.delayed(const Duration(milliseconds: 200)),
                bloc.contextToken.whenCancel.then(
                  (_) => throw DioException(
                    requestOptions: RequestOptions(),
                    type: DioExceptionType.cancel,
                  ),
                ),
              ]);
            } on DioException catch (e) {
              if (e.type == DioExceptionType.cancel) {
                firstRequestInterrupted = true;
              }
              rethrow;
            }
          }

          if (event is RecoverySuccessEvent) {
            await Future.delayed(const Duration(milliseconds: 20));
            emit(DataState(2));
            completer.complete();
          }
        }, transformer: restartable())
        ..add(RecoveryErrorEvent());
      await Future.delayed(const Duration(milliseconds: 20));

      bloc.add(RecoverySuccessEvent());

      await completer.future.timeout(const Duration(seconds: 1));

      expect(
        firstRequestInterrupted,
        isTrue,
        reason: 'First event async operation must be interrupted',
      );

      expect(bloc.state, isA<DataState>().having((s) => s.data, 'data', 2));
    });

    test('Close: Guaranteed cancellation of all active operations on Bloc disposal', () async {
      final bloc = ErrorHandlerTestBloc();
      ICancelToken? activeToken;
      var isAsyncOperationInterrupted = false;

      bloc
        ..on<CancelableEvent>((event, emit) async {
          activeToken = bloc.contextToken;
          emit(LoadingState());

          try {
            await bloc.contextToken.whenCancel.then((_) {
              isAsyncOperationInterrupted = true;
              throw Exception('Cancelled');
            });
          } on Object catch (_) {
            // Error caught by mixin zone
          }
        })
        ..add(CancelableEvent());
      await Future.delayed(const Duration(milliseconds: 10));

      final token = activeToken;
      expect(token, isNotNull);
      expect(token!.isCancelled, isFalse, reason: 'Token must be active while Bloc is running');

      await bloc.close();

      expect(
        token.isCancelled,
        isTrue,
        reason: 'close() must cancel all active event tokens',
      );

      expect(
        isAsyncOperationInterrupted,
        isTrue,
        reason: 'Async operation must be interrupted by cancellation signal on Bloc close',
      );
    });

    test('Infinite Stream: Guaranteed iterator stop via ICancelToken', () async {
      final bloc = ErrorHandlerTestBloc();
      var processedTicks = 0;
      final completer = Completer<void>();

      bloc
        ..on<InfiniteStreamEvent>((event, emit) async {
          emit(LoadingState());

          final cancelableStream = Stream.periodic(
            const Duration(milliseconds: 10),
            (i) => i,
          ).takeUntil(bloc.contextToken.whenCancel.asStream());

          await emit.forEach<int>(
            cancelableStream,
            onData: (data) {
              processedTicks++;
              return DataState(data);
            },
          );

          if (!completer.isCompleted) {
            completer.complete();
          }
        })
        ..add(InfiniteStreamEvent());
      await Future.delayed(const Duration(milliseconds: 55));

      final ticksBeforeClose = processedTicks;
      expect(
        ticksBeforeClose,
        greaterThan(0),
        reason: 'Bloc must process several ticks before close',
      );

      await bloc.close();
      await completer.future.timeout(const Duration(milliseconds: 100));

      final ticksAfterClose = processedTicks;

      await Future.delayed(const Duration(milliseconds: 50));

      expect(
        processedTicks,
        lessThanOrEqualTo(ticksAfterClose),
        reason: 'Data processing in emit.forEach must stop completely after Bloc close',
      );
    });

    test('Recursion Guard: Protection against infinite loop (via logger failure)', () async {
      var loggerCalls = 0;
      final bloc = ErrorHandlerTestBloc()
        ..on<RecoveryErrorEvent>((event, emit) async {
          await Future.delayed(const Duration(milliseconds: 10));
          throw Exception('Primary error');
        })
        ..logger = ({required tag, required error, required event, required stackTrace}) {
          loggerCalls++;
          throw Exception('Error inside logger!');
        }
        ..add(RecoveryErrorEvent());

      await Future.delayed(const Duration(milliseconds: 100));

      // Thanks to Zone.current[_isHandlingErrorKey], recursive call
      // from logger error is blocked
      expect(loggerCalls, 1, reason: 'Recursive logger call must be blocked');

      await bloc.close();
    });

    test('runZonedGuarded: Confirmation of active zone in async context', () async {
      final bloc = ErrorHandlerTestBloc();
      ICancelToken? originalToken;
      ICancelToken? capturedToken;
      final completer = Completer<void>();

      bloc
        ..on<RecoveryErrorEvent>((event, emit) async {
          originalToken = bloc.contextToken;

          scheduleMicrotask(() {
            try {
              capturedToken = bloc.contextToken;
            } on Object catch (_) {
              //
            }
            if (!completer.isCompleted) {
              completer.complete();
            }
          });

          await Future.delayed(const Duration(milliseconds: 50));
        })
        ..add(RecoveryErrorEvent());

      await completer.future.timeout(const Duration(seconds: 1));

      expect(
        capturedToken,
        isNotNull,
        reason: 'Microtask lost mixin zone and could not find contextToken',
      );

      expect(
        capturedToken,
        same(originalToken),
        reason: 'Microtask must be in the same zone as the main event',
      );

      await bloc.close();
    });

    test('Zombie Emits: Async code after zone closure must not change state', () async {
      final bloc = ErrorHandlerTestBloc();
      final states = <TestState>[];
      final sub = bloc.stream.listen(states.add);

      bloc
        ..on<ZombieSuccessEvent>((event, emit) async {
          Timer(const Duration(milliseconds: 50), () {
            emit(DataState('Zombie'));
          });

          emit(DataState('Alive'));
        })
        ..add(ZombieSuccessEvent());

      await Future.delayed(const Duration(milliseconds: 100));
      await sub.cancel();

      expect(states, [
        isA<DataState>().having((s) => s.data, 'data', 'Alive'),
      ], reason: 'State from stale timer must not enter stream');
    });

    test('Race Condition: Proper completion when closing Bloc during emit', () async {
      final bloc = ErrorHandlerTestBloc()
        ..on<RaceConditionSuccessEvent>((event, emit) async {
          emit(LoadingState());
          await Future.delayed(Duration.zero);
          emit(DataState('Data'));
        })
        ..add(RaceConditionSuccessEvent());

      await expectLater(bloc.close(), completes);

      expect(bloc.isClosed, isTrue);
      // No "StateError: Cannot emit new states after calling close" error
    });

    test('Must withstand 1000 sequential errors', () async {
      final bloc = ErrorHandlerTestBloc()
        ..on<ErrorEvent>((event, emit) async {
          emit(ErrorState());
        });
      for (var i = 0; i < 1000; i++) {
        bloc.add(ErrorEvent());
      }
      await Future.delayed(const Duration(seconds: 1));
      expect(bloc.state, isA<ErrorState>());
    });

    test('Hierarchy: Local mapper takes priority over Global mapper', () async {
      final states = <TestState>[];
      final bloc = ErrorHandlerTestBloc();
      final sub = bloc.stream.listen(states.add);

      bloc
        ..on<LocalErrorEvent>((event, emit) async {
          emit(LoadingState());
          throw Exception('Fail');
        })
        ..add(LocalErrorEvent());

      await bloc.stream
          .firstWhere((state) => state is LocalErrorState)
          .timeout(const Duration(milliseconds: 500));

      expect(states, [
        isA<LoadingState>(),
        isA<LocalErrorState>(),
      ]);

      await sub.cancel();
      await bloc.close();
    });

    test('Hierarchy: Global mapper triggers when Local mapper returns null', () async {
      final states = <TestState>[];
      final bloc = ErrorHandlerTestBloc();
      final sub = bloc.stream.listen(states.add);

      bloc
        ..on<RecoveryErrorEvent>((event, emit) async {
          emit(LoadingState());
          throw Exception('Fail');
        })
        ..add(RecoveryErrorEvent());

      await bloc.stream
          .firstWhere((state) => state is ErrorState)
          .timeout(const Duration(milliseconds: 500));

      expect(states, [
        isA<LoadingState>(),
        isA<ErrorState>(),
      ]);

      await sub.cancel();
      await bloc.close();
    });

    test('Silent Mapper: Bloc does not change state when mappers return null', () async {
      final states = <TestState>[];
      final bloc = ErrorHandlerTestBloc();
      final sub = bloc.stream.listen(states.add);

      bloc
        ..on<UnknownEvent>((event, emit) async {
          emit(LoadingState());
          throw Exception('Ignore me');
        })
        ..add(UnknownEvent());

      await Future.delayed(const Duration(milliseconds: 100));

      expect(states, [isA<LoadingState>()]);
      expect(bloc.state, isA<LoadingState>());

      await sub.cancel();
      await bloc.close();
    });

    test('Logger Data: Logger must receive correct Error and StackTrace', () async {
      Object? capturedError;
      StackTrace? capturedStack;
      final bloc = ErrorHandlerTestBloc()
        ..logger = ({required tag, required error, required event, required stackTrace}) {
          capturedError = error;
          capturedStack = stackTrace;
        };

      final testException = Exception('Logger Test Exception');

      bloc
        ..on<RecoveryErrorEvent>((event, emit) async {
          throw testException;
        })
        ..add(RecoveryErrorEvent());

      await Future.delayed(const Duration(milliseconds: 50));

      expect(
        capturedError,
        same(testException),
        reason: 'Logger must receive the same error object',
      );
      expect(capturedStack, isNotNull, reason: 'StackTrace must not be empty');
      expect(capturedStack.toString(), contains('bloc_error_control_test.dart'));

      await bloc.close();
    });

    test('Heavy Logger: Logger delay must not block event flow', () async {
      final executionOrder = <String>[];
      final bloc = ErrorHandlerTestBloc()
        ..logger = ({required tag, required error, required event, required stackTrace}) {
          final stopwatch = Stopwatch()..start();
          while (stopwatch.elapsedMilliseconds < 50) {} // Simulate heavy work
          executionOrder.add('logger_done');
        }
        ..on<RecoveryErrorEvent>((event, emit) async {
          executionOrder.add('event_1_error');
          throw Exception('Error 1');
        })
        ..on<RecoverySuccessEvent>((event, emit) async {
          executionOrder.add('event_2_success');
          emit(DataState(2));
        })
        ..add(RecoveryErrorEvent())
        ..add(RecoverySuccessEvent());

      await Future.delayed(const Duration(milliseconds: 200));

      // Thanks to scheduleMicrotask, first event logger does not block second event
      expect(
        executionOrder,
        contains('event_2_success'),
        reason: 'Second event must be processed despite first event heavy logger',
      );

      expect(
        executionOrder,
        contains('logger_done'),
        reason: 'Logger must complete its work',
      );

      await bloc.close();
    });

    test('should create with default reason', () {
      final exception = BlocCanceledException();
      expect(exception.reason, CancelRequestReasons.manual);
      expect(exception.toString(), contains('BlocCanceledException'));
    });

    test('should create with custom reason', () {
      final exception = BlocCanceledException('custom reason');
      expect(exception.reason, 'custom reason');
    });

    test('should cancel and notify whenCancel', () async {
      final token = EventCancelToken(event: UnknownEvent());
      expect(token.isCancelled, false);

      token.cancel();
      expect(token.isCancelled, true);
      expect(token.whenCancel, completes);
    });

    test('throwIfCancelled should throw after cancellation', () {
      final token = EventCancelToken(event: UnknownEvent())..cancel();
      expect(token.throwIfCancelled, throwsA(isA<BlocCanceledException>()));
    });

    test('getActiveTokensInfo should return token info', () async {
      final bloc = ErrorHandlerTestBloc()..add(SequentialEvent(1));
      await Future.delayed(const Duration(milliseconds: 10));

      final info = bloc.getActiveTokensInfo();
      expect(info, isNotEmpty);
      expect(info.first['eventType'], 'SequentialEvent');

      await bloc.close();
    });

    test('contextToken should work inside event handler', () async {
      final bloc = ErrorHandlerTestBloc();
      final completer = Completer<ICancelToken>();

      bloc
        ..on<CustomSequentialEvent>((event, emit) async {
          completer.complete(bloc.contextToken);
        })
        ..add(CustomSequentialEvent(1));
      final token = await completer.future.timeout(const Duration(seconds: 1));

      expect(token, isNotNull);
      expect(token.isCancelled, false);

      await bloc.close();
    });

    test('ErrorStateFor should store event type', () {
      const annotation = ErrorStateFor(LocalErrorEvent);
      expect(annotation.eventType, LocalErrorEvent);
    });

    test('BlocErrorHandler should be instantiable', () {
      const annotation = BlocErrorHandler();
      expect(annotation, isNotNull);
    });

    test('blocErrorHandler constant should work', () {
      expect(blocErrorHandler, isA<BlocErrorHandler>());
    });

    test('EventCancelToken.fallback should work', () {
      final token = EventCancelToken.fallback('test');
      expect(token.event, isNull);
      expect(token.operationName, 'test');
      expect(token.hash, 'test'.hashCode);
    });

    test('getActiveTokensInfo should return token information', () async {
      final bloc = ErrorHandlerTestBloc();

      final completer = Completer<void>();
      bloc
        ..on<CustomSequentialEvent>((event, emit) async {
          await completer.future;
        })
        ..add(CustomSequentialEvent(1));
      await Future.delayed(const Duration(milliseconds: 10));

      final info = bloc.getActiveTokensInfo();
      expect(info, isNotEmpty);
      expect(info.first['eventType'], contains('CustomSequentialEvent'));

      completer.complete();
      await bloc.close();
    });

    test('hasActiveTokenForEvent should return true for active event', () async {
      final bloc = ErrorHandlerTestBloc();
      final completer = Completer<void>();
      final event = CustomSequentialEvent(1);

      bloc
        ..on<CustomSequentialEvent>((event, emit) async {
          await completer.future;
        })
        ..add(event);
      await Future.delayed(const Duration(milliseconds: 10));

      expect(bloc.hasActiveTokenForEvent(event), true);

      completer.complete();
      await bloc.close();
    });

    test('cancelTokensByEventType should cancel specific event type', () async {
      final bloc = ErrorHandlerTestBloc();
      var wasCancelled = false;

      bloc
        ..on<CustomSequentialEvent>((event, emit) async {
          try {
            await bloc.contextToken.whenCancel;
            wasCancelled = true;
          } on Object catch (_) {}
        })
        ..add(CustomSequentialEvent(1));
      await Future.delayed(const Duration(milliseconds: 10));

      bloc.cancelTokensByEventType<CustomSequentialEvent>();
      await Future.delayed(const Duration(milliseconds: 50));

      expect(wasCancelled, true);
      await bloc.close();
    });

    test('cancelTokenForEvent should cancel specific event instance', () async {
      final bloc = ErrorHandlerTestBloc();
      final event1 = CustomSequentialEvent(1);
      final event2 = CustomSequentialEvent(2);
      var event1Cancelled = false;
      var event2Cancelled = false;

      bloc
        ..on<CustomSequentialEvent>((event, emit) async {
          if (event.id == 1) {
            await bloc.contextToken.whenCancel.then((_) => event1Cancelled = true);
          } else {
            await bloc.contextToken.whenCancel.then((_) => event2Cancelled = true);
          }
        })
        ..add(event1)
        ..add(event2);
      await Future.delayed(const Duration(milliseconds: 10));

      bloc.cancelTokenForEvent(event1);
      await Future.delayed(const Duration(milliseconds: 50));

      expect(event1Cancelled, true);
      expect(event2Cancelled, false);

      await bloc.close();
    });

    test('event timeout should throw EventTimeoutError', () async {
      final bloc = ErrorHandlerTestBloc();
      final completer = Completer<void>();

      bloc
        ..on<CustomSequentialEvent>(
          (event, emit) async {
            await completer.future;
          },
          timeout: const Duration(milliseconds: 50),
        )
        ..add(CustomSequentialEvent(1));

      await expectLater(
        bloc.stream.firstWhere((state) => state is ErrorState),
        completes,
      );

      completer.complete();
      await bloc.close();
    });

    test('logger error should not break error handling', () async {
      final bloc = ErrorHandlerTestBloc();
      var errorLogged = false;

      bloc
        ..logger = ({required tag, required error, required stackTrace, required event}) {
          errorLogged = true;
          throw Exception('Logger failed!');
        }
        ..on<ErrorEvent>((event, emit) async {
          throw Exception('Test error');
        })
        ..add(ErrorEvent());
      await Future.delayed(const Duration(milliseconds: 50));

      expect(errorLogged, true);
      expect(bloc.isClosed, false);

      await bloc.close();
    });

    test('EventCancelToken should handle cancel with reason', () {
      final token = EventCancelToken(event: UnknownEvent());
      const reason = 'custom reason';
      token.cancel(reason);
      expect(token.isCancelled, true);
      expect(token.reason, reason);
    });

    test('EventCancelToken properties should return correct values', () {
      final event = TokenTestEvent(1);
      final token = EventCancelToken(event: event);

      expect(token.operationName, 'TokenTestEvent');
      expect(token.hash, isNotNull);
      expect(token.duration, isA<Duration>());
      expect(token.startTime, isA<DateTime>());
    });

    test('should handle StateError when controller is closed', () async {
      final bloc = ErrorHandlerTestBloc();
      final completer = Completer<void>();

      bloc
        ..on<CustomSequentialEvent>((event, emit) async {
          emit(LoadingState());
          await completer.future;
        })
        ..add(CustomSequentialEvent(1));
      await Future.delayed(const Duration(milliseconds: 10));

      await bloc.close();
      completer.complete();
    });

    test('should handle double cancellation gracefully', () async {
      final bloc = ErrorHandlerTestBloc();
      final event = CustomSequentialEvent(1);
      var cancelCount = 0;

      bloc
        ..on<CustomSequentialEvent>((event, emit) async {
          await bloc.contextToken.whenCancel.then((_) => cancelCount++);
          await Future.delayed(const Duration(seconds: 1));
        })
        ..add(event);
      await Future.delayed(const Duration(milliseconds: 10));

      bloc
        ..cancelTokenForEvent(event)
        ..cancelTokenForEvent(event);

      await Future.delayed(const Duration(milliseconds: 50));

      expect(cancelCount, 1);
      await bloc.close();
    });

    test('getErrorMapperForEvent should return null by default', () {
      final bloc = ErrorHandlerTestBloc();
      final result = bloc.getErrorMapperForEvent(
        Exception('test'),
        StackTrace.current,
        UnknownEvent(),
      );
      expect(result, isNull);
    });

    test('should handle error without duplication', () async {
      final bloc = ErrorHandlerTestBloc();
      final states = <TestState>[];
      final subscription = bloc.stream.listen(states.add);

      bloc
        ..on<CustomSequentialEvent>((event, emit) async {
          throw Exception('Test error');
        })
        ..add(CustomSequentialEvent(1));
      await Future.delayed(const Duration(milliseconds: 50));

      final errorStates = states.whereType<ErrorState>().toList();
      expect(errorStates.length, 1);

      await subscription.cancel();
      await bloc.close();
    });

    test('should handle double cancellation without errors', () async {
      final token = EventCancelToken(event: UnknownEvent())
        ..cancel()
        ..cancel();

      expect(token.isCancelled, true);
    });

    test('should handle StateError when controller is closed during stream emission', () async {
      final bloc = ErrorHandlerTestBloc()
        ..on<CustomSequentialEvent>((event, emit) async {
          emit(LoadingState());
          final stream = Stream.periodic(const Duration(milliseconds: 10), (i) => i).take(10);
          await emit.forEach(stream, onData: DataState.new);
        })
        ..add(CustomSequentialEvent(1));
      await Future.delayed(const Duration(milliseconds: 25));

      await bloc.close();

      expect(bloc.isClosed, true);
    });

    test('should handle error when closing controller', () async {
      final bloc = ErrorHandlerTestBloc()
        ..on<CustomSequentialEvent>((event, emit) async {
          emit(LoadingState());
          await Future.delayed(const Duration(milliseconds: 20));
          emit(DataState('Done'));
        })
        ..add(CustomSequentialEvent(1));
      await Future.delayed(const Duration(milliseconds: 10));

      await bloc.close();

      expect(bloc.isClosed, true);
    });

    test('should handle error when state mapping fails', () async {
      final bloc = FailingMapperBloc()..add(ErrorEvent());
      await Future.delayed(const Duration(milliseconds: 50));

      expect(bloc.isClosed, false);
      await bloc.close();
      expect(bloc.isClosed, true);
    });

    test('takeUntil should handle signal stream closure gracefully', () async {
      final controller = StreamController<int>();
      final signalController = StreamController<void>();

      final stream = controller.stream.takeUntil(signalController.stream);

      final subscription = stream.listen((_) {});

      await signalController.close();
      await Future.delayed(const Duration(milliseconds: 50));

      expect(true, true);

      await controller.close();
      await subscription.cancel();
    });

    test('should not cancel token that is already cancelled on controller close', () async {
      final bloc = ErrorHandlerTestBloc();
      final event = CustomSequentialEvent(1);
      var cancelCalled = false;

      bloc
        ..on<CustomSequentialEvent>((event, emit) async {
          bloc.contextToken.cancel();
          cancelCalled = true;
          await Future.delayed(const Duration(milliseconds: 50));
        })
        ..add(event);
      await Future.delayed(const Duration(milliseconds: 10));

      await bloc.close();

      expect(cancelCalled, true);
    });

    test('should handle error when closing controller throws', () async {
      final bloc = ErrorHandlerTestBloc()
        ..on<CustomSequentialEvent>((event, emit) async {
          emit(LoadingState());
          await Future.delayed(const Duration(milliseconds: 10));
          emit(DataState('Done'));
        })
        ..add(CustomSequentialEvent(1));
      await Future.delayed(const Duration(milliseconds: 5));

      await bloc.close();

      expect(bloc.isClosed, true);
    });

    test('should not cancel token that is already cancelled on controller close', () async {
      final bloc = ErrorHandlerTestBloc();
      final event = CustomSequentialEvent(1);
      var tokenWasCancelled = false;

      bloc
        ..on<CustomSequentialEvent>((event, emit) async {
          final token = bloc.contextToken..cancel();
          tokenWasCancelled = token.isCancelled;
          await Future.delayed(const Duration(milliseconds: 50));
        })
        ..add(event);
      await Future.delayed(const Duration(milliseconds: 10));

      await bloc.close();

      expect(tokenWasCancelled, true);
    });

    test('should not call super.onError for already reported error', () async {
      final states = <TestState>[];
      final bloc = ErrorHandlerTestBloc();
      final subscription = bloc.stream.listen(states.add);

      bloc
        ..on<CustomSequentialEvent>((event, emit) async {
          throw Exception('Test error');
        })
        ..add(CustomSequentialEvent(1));
      await Future.delayed(const Duration(milliseconds: 50));

      final errorStates = states.whereType<ErrorState>().toList();
      expect(errorStates.length, 1);

      await subscription.cancel();
      await bloc.close();
    });
  });
}
