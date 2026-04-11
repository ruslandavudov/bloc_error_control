import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:bloc_error_control/bloc_error_control.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

// Events
sealed class TestEvent {}

class EventA extends TestEvent {}

class EventB extends TestEvent {}

// Bloc with our magic
class SignalTestBloc extends Bloc<TestEvent, int> with BlocErrorControlMixin<TestEvent, int> {
  @override
  String get tag => 'SignalTestBloc';

  SignalTestBloc() : super(0) {
    on<EventA>((event, emit) async {
      emitSignal('signal_a_1');
      await contextToken.delay(const Duration(milliseconds: 100));
      emitSignal('signal_a_2');
    }, transformer: restartable());

    on<EventB>((event, emit) async {
      emitSignal('signal_b');
    });
  }

  @override
  int? mapErrorToState(Object error, StackTrace s, TestEvent? event) => null;
}

class ErrorSignalBloc extends Bloc<TestEvent, int> with BlocErrorControlMixin<TestEvent, int> {
  @override
  String get tag => 'ErrorSignalBloc';

  ErrorSignalBloc() : super(0) {
    on<EventA>((event, emit) async {
      throw Exception('fail');
    });
  }

  @override
  int? mapErrorToState(Object error, StackTrace s, TestEvent? event) => null;

  @override
  Object? mapErrorToSignal(Object error, StackTrace stack, TestEvent? event) {
    return 'error_signal';
  }
}

// Typed signal
sealed class MySignal {
  const MySignal();

  factory MySignal.message(String text) = MessageSignal;

  factory MySignal.navigateTo(String route) = NavigateSignal;
}

@immutable
class MessageSignal extends MySignal {
  final String text;

  const MessageSignal(this.text);

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is MessageSignal && text == other.text;

  @override
  int get hashCode => text.hashCode;
}

@immutable
class NavigateSignal extends MySignal {
  final String route;

  const NavigateSignal(this.route);

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is NavigateSignal && route == other.route;

  @override
  int get hashCode => route.hashCode;
}

// Bloc for typed signals test
class TypedSignalBloc extends Bloc<TestEvent, int> with BlocErrorControlMixin<TestEvent, int> {
  @override
  String get tag => 'TypedSignalBloc';

  TypedSignalBloc() : super(0) {
    on<EventA>((event, emit) async {
      emitSignal(MySignal.message('Hello World'));
      await Future.delayed(const Duration(milliseconds: 50));
      emitSignal(MySignal.navigateTo('/home'));
    });
  }

  @override
  int? mapErrorToState(Object error, StackTrace s, TestEvent? event) => null;
}

// Bloc for testing signals after close
class CloseTestBloc extends Bloc<TestEvent, int> with BlocErrorControlMixin<TestEvent, int> {
  @override
  String get tag => 'CloseTestBloc';

  CloseTestBloc() : super(0) {
    on<EventA>((event, emit) async {
      emitSignal('should be sent before close');
    });
  }

  // Method for testing signal after close
  @visibleForTesting
  void tryEmitAfterClose() {
    emitSignal('should NOT be sent after close');
  }

  @override
  int? mapErrorToState(Object error, StackTrace s, TestEvent? event) => null;
}

// Bloc for signalsFor<E> test (all signals)
class AllSignalsBloc extends Bloc<TestEvent, int> with BlocErrorControlMixin<TestEvent, int> {
  @override
  String get tag => 'AllSignalsBloc';

  AllSignalsBloc() : super(0) {
    on<EventA>((event, emit) async {
      emitSignal('signal_from_A');
    });

    on<EventB>((event, emit) async {
      emitSignal('signal_from_B');
    });
  }

  @override
  int? mapErrorToState(Object error, StackTrace s, TestEvent? event) => null;
}

// Bloc for context-aware mapErrorToSignal test
class ContextAwareErrorBloc extends Bloc<TestEvent, int>
    with BlocErrorControlMixin<TestEvent, int> {
  @override
  String get tag => 'ContextAwareErrorBloc';

  ContextAwareErrorBloc() : super(0) {
    on<EventA>((event, emit) async {
      throw Exception('error from A');
    });

    on<EventB>((event, emit) async {
      throw Exception('error from B');
    });
  }

  @override
  int? mapErrorToState(Object error, StackTrace s, TestEvent? event) => null;

  @override
  Object? mapErrorToSignal(Object error, StackTrace stack, TestEvent? event) {
    if (event is EventA) {
      return 'error_from_A';
    }
    // EventB — don't send signal
    return null;
  }
}

// Bloc for CancelableDelay test
class CancelableDelayBloc extends Bloc<TestEvent, int> with BlocErrorControlMixin<TestEvent, int> {
  @override
  String get tag => 'CancelableDelayBloc';

  CancelableDelayBloc() : super(0) {
    on<EventA>((event, emit) async {
      emitSignal('start');
      await contextToken.delay(const Duration(milliseconds: 100));
      emitSignal('after_delay');
    }, transformer: restartable());
  }

  @override
  int? mapErrorToState(Object error, StackTrace s, TestEvent? event) => null;
}
