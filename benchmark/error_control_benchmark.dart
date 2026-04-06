// ignore_for_file: avoid_print, depend_on_referenced_packages
import 'package:benchmark_harness/benchmark_harness.dart';
import 'package:bloc/bloc.dart';
import 'package:bloc_error_control/src/mixins/bloc_error_control_mixin.dart';
import 'package:bloc_error_control/src/models/event_cancel_token.dart';

sealed class BenchEvent {
  const BenchEvent();
}

class RunEvent extends BenchEvent {
  const RunEvent();
}

sealed class BenchState {
  const BenchState();
}

class InitialState extends BenchState {
  const InitialState();
}

class DataState extends BenchState {
  const DataState();
}

class PlainBloc extends Bloc<BenchEvent, BenchState> {
  PlainBloc() : super(const InitialState()) {
    on<RunEvent>((event, emit) => emit(const DataState()));
  }
}

class EnhancedBloc extends Bloc<BenchEvent, BenchState>
    with BlocErrorHandlerMixin<BenchEvent, BenchState> {
  EnhancedBloc() : super(const InitialState()) {
    on<RunEvent>((event, emit) => emit(const DataState()));
  }

  @override
  String get tag => 'Benchmark';

  @override
  BenchState? mapErrorToState(Object error, StackTrace s, BenchEvent event) => null;

  @override
  BenchState? getErrorMapperForEvent(Object error, StackTrace s, BenchEvent event) => null;
}

class TimeoutBloc extends Bloc<BenchEvent, BenchState>
    with BlocErrorHandlerMixin<BenchEvent, BenchState> {
  TimeoutBloc() : super(const InitialState()) {
    on<RunEvent>(
      (event, emit) => emit(const DataState()),
      timeout: const Duration(seconds: 1),
    );
  }

  @override
  String get tag => 'BenchmarkTimeout';

  @override
  BenchState? mapErrorToState(Object error, StackTrace s, BenchEvent event) => null;

  @override
  BenchState? getErrorMapperForEvent(Object error, StackTrace s, BenchEvent event) => null;
}

class PureBlocBenchmark extends BenchmarkBase {
  PureBlocBenchmark() : super('Pure BLoC (100 ev)');
  late PlainBloc bloc;

  @override
  void setup() => bloc = PlainBloc();

  @override
  void run() {
    for (var i = 0; i < 100; i++) {
      bloc.add(const RunEvent());
    }
  }

  @override
  void teardown() => bloc.close();
}

class EnhancedBlocBenchmark extends BenchmarkBase {
  EnhancedBlocBenchmark() : super('With ErrorHandlerMixin (100 ev)');
  late EnhancedBloc bloc;

  @override
  void setup() => bloc = EnhancedBloc();

  @override
  void run() {
    for (var i = 0; i < 100; i++) {
      bloc.add(const RunEvent());
    }
  }

  @override
  void teardown() => bloc.close();
}

class TimeoutBlocBenchmark extends BenchmarkBase {
  TimeoutBlocBenchmark() : super('With Timeout (100 ev)');
  late TimeoutBloc bloc;

  @override
  void setup() => bloc = TimeoutBloc();

  @override
  void run() {
    for (var i = 0; i < 100; i++) {
      bloc.add(const RunEvent());
    }
  }

  @override
  void teardown() => bloc.close();
}

class ThrowIfCancelledBenchmark extends BenchmarkBase {
  ThrowIfCancelledBenchmark() : super('throwIfCancelled (1000 calls)');
  late EventCancelToken<RunEvent> token;

  @override
  void setup() => token = EventCancelToken(event: const RunEvent());

  @override
  void run() {
    for (var i = 0; i < 1000; i++) {
      token.throwIfCancelled();
    }
  }
}

void main() {
  print('--- BLoC Performance Comparison v1.0.0 ---');

  PureBlocBenchmark().report();
  EnhancedBlocBenchmark().report();
  TimeoutBlocBenchmark().report();

  print('\n--- Utility Performance ---');
  ThrowIfCancelledBenchmark().report();
}
