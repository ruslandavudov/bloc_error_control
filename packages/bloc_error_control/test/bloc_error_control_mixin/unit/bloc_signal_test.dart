import 'dart:async';

import 'package:bloc_error_control/bloc_error_control.dart';
import 'package:test/test.dart';

import '../blocs/signal_test_bloc.dart';

void main() {
  group('Signals Integrated Tests', () {
    test('signalsFor<T> should filter signals by event type', () async {
      final bloc = SignalTestBloc();
      final caughtA = [];
      final caughtB = [];

      // Subscribe to different event types
      final subA = bloc.signalsFor<EventA>().listen(caughtA.add);
      final subB = bloc.signalsFor<EventB>().listen(caughtB.add);

      bloc
        ..add(EventA())
        ..add(EventB());

      await Future.delayed(const Duration(milliseconds: 200));

      expect(caughtA, contains('signal_a_1'));
      expect(caughtA, contains('signal_a_2'));
      expect(caughtA, isNot(contains('signal_b'))); // Filtering works

      expect(caughtB, contains('signal_b'));
      expect(caughtB, isNot(contains('signal_a_1')));

      await subA.cancel();
      await subB.cancel();
      await bloc.close();
    });

    test('signals from canceled zones should not be emitted', () async {
      final bloc = SignalTestBloc();
      final caughtSignals = [];

      bloc.signalsFor<EventA>().listen(caughtSignals.add);

      // Spam EventA three times. Restartable will cancel the first two.
      bloc
        ..add(EventA()) // Will be cancelled during delay
        ..add(EventA()) // Will be cancelled during delay
        ..add(EventA()); // Should survive

      await Future.delayed(const Duration(milliseconds: 300));

      // Count how many times 'signal_a_1' arrived (before delay, may sneak through)
      // And how many times 'signal_a_2' arrived (after delay)
      final countStart = caughtSignals.where((s) => s == 'signal_a_1').length;
      final countEnd = caughtSignals.where((s) => s == 'signal_a_2').length;

      expect(countStart, equals(3)); // All three managed to start
      expect(countEnd, equals(1)); // But only the last one finished!

      await bloc.close();
    });

    test('mapErrorToSignal should convert exceptions to signals', () async {
      final bloc = ErrorSignalBloc();
      final caught = [];

      bloc.signalsFor<EventA>().listen(caught.add);

      bloc.add(EventA());
      await Future.delayed(const Duration(milliseconds: 50));

      expect(caught, contains('error_signal'));
      await bloc.close();
    });

    test('should emit typed signals', () async {
      final bloc = TypedSignalBloc();
      final caught = <MySignal>[];

      // Remove cast, signalsFor returns Stream<Object>
      bloc.signalsFor<EventA>().listen((signal) {
        // Manual casting
        if (signal is MySignal) {
          caught.add(signal);
        }
      });

      bloc.add(EventA());
      await Future.delayed(const Duration(milliseconds: 100));

      expect(caught.length, equals(2));
      expect(caught[0], equals(MySignal.message('Hello World')));
      expect(caught[1], equals(MySignal.navigateTo('/home')));

      await bloc.close();
    });

    test('signals after close should be ignored', () async {
      final bloc = CloseTestBloc();
      final caught = [];

      bloc.signalsFor<EventA>().listen(caught.add);

      // Normal signal
      bloc.add(EventA());
      await Future.delayed(const Duration(milliseconds: 10));

      // Close
      await bloc.close();

      // Try to send a signal after close
      bloc.tryEmitAfterClose();
      await Future.delayed(const Duration(milliseconds: 10));

      expect(caught.length, equals(1));
      expect(caught.first, equals('should be sent before close'));
    });

    test('signalsFor<E> should return all signals', () async {
      final bloc = AllSignalsBloc();
      final caught = [];

      // Subscribe to base type — receive all signals
      bloc.signalsFor<TestEvent>().listen(caught.add);

      bloc
        ..add(EventA())
        ..add(EventB());

      await Future.delayed(const Duration(milliseconds: 50));

      expect(caught, contains('signal_from_A'));
      expect(caught, contains('signal_from_B'));
      expect(caught.length, equals(2));

      await bloc.close();
    });

    test('mapErrorToSignal should be context-aware', () async {
      final bloc = ContextAwareErrorBloc();
      final caught = [];

      bloc.signalsFor<TestEvent>().listen(caught.add);

      bloc
        ..add(EventA()) // Should send a signal
        ..add(EventB()); // Should not send a signal

      await Future.delayed(const Duration(milliseconds: 50));

      expect(caught.length, equals(1));
      expect(caught.first, equals('error_from_A'));

      await bloc.close();
    });

    test('CancelableDelay should be cancelled when token is cancelled', () async {
      final bloc = CancelableDelayBloc();
      final caught = [];

      bloc.signalsFor<EventA>().listen(caught.add);

      // Send three events with restartable()
      bloc
        ..add(EventA()) // will be cancelled
        ..add(EventA()) // will be cancelled
        ..add(EventA()); // will survive

      await Future.delayed(const Duration(milliseconds: 250));

      // Check: 'start' should be present for all three
      // 'after_delay' — only for the last one
      final startCount = caught.where((s) => s == 'start').length;
      final afterDelayCount = caught.where((s) => s == 'after_delay').length;

      expect(startCount, equals(3));
      expect(afterDelayCount, equals(1));

      await bloc.close();
    });

    test('CancelableDelay should throw BlocCanceledException when already cancelled', () async {
      final bloc = CancelableDelayBloc();

      // Create a token and cancel it immediately
      final token = EventCancelToken(event: EventA())..cancel();

      // Expect delay to throw an exception
      expect(
        () => token.delay(const Duration(milliseconds: 10)),
        throwsA(isA<BlocCanceledException>()),
      );

      await bloc.close();
    });

    test('should emit typed signals', () async {
      final bloc = TypedSignalBloc();
      final caught = <MySignal>[];

      // Add type casting
      bloc.signalsFor<EventA>().listen((signal) {
        if (signal is MySignal) {
          caught.add(signal);
        }
      });

      bloc.add(EventA());
      await Future.delayed(const Duration(milliseconds: 100));

      expect(caught.length, equals(2));
      expect(caught[0], equals(MySignal.message('Hello World')));
      expect(caught[1], equals(MySignal.navigateTo('/home')));

      await bloc.close();
    });
  });
}
