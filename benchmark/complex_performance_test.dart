// ignore_for_file: avoid_print, depend_on_referenced_packages
import 'dart:async';
import 'dart:io';

import 'package:bloc/bloc.dart';
import 'package:bloc_error_control/src/mixins/bloc_error_control_mixin.dart';

sealed class BenchEvent {
  const BenchEvent();
}

class RunEvent extends BenchEvent {
  final int id;
  const RunEvent(this.id);
}

sealed class BenchState {
  const BenchState();
}

class InitialState extends BenchState {
  const InitialState();
}

class DataState extends BenchState {
  final int id;
  const DataState(this.id);
}

class FastBloc extends Bloc<BenchEvent, BenchState>
    with BlocErrorHandlerMixin<BenchEvent, BenchState> {
  FastBloc() : super(const InitialState()) {
    on<RunEvent>((event, emit) => emit(DataState(event.id)));
  }

  @override
  String get tag => 'Bench';

  @override
  BenchState? mapErrorToState(Object e, StackTrace s, BenchEvent ev) => null;

  @override
  BenchState? getErrorMapperForEvent(Object e, StackTrace s, BenchEvent ev) => null;
}

void main() async {
  print('=== STARTING COMPLEX BENCHMARKS v1.0.0 ===\n');

  await runAllBenchmarks();

  print('=== BENCHMARKS COMPLETED ===');
}

Future<void> runAllBenchmarks() async {
  final bloc = FastBloc();
  const iterations = 1000;

  // 1. LATENCY
  final sw = Stopwatch();
  final completer = Completer<void>();
  var receivedCount = 0;
  var totalMicros = 0;

  final sub = bloc.stream.listen((state) {
    if (state is DataState) {
      sw.stop();
      totalMicros += sw.elapsedMicroseconds;
      receivedCount++;
      if (receivedCount == iterations) {
        completer.complete();
      } else {
        sw
          ..reset()
          ..start();
        bloc.add(RunEvent(receivedCount));
      }
    }
  });

  print('1. Running Latency Test...');
  sw.start();
  bloc.add(const RunEvent(0));
  await completer.future.timeout(const Duration(seconds: 5));
  print('   Average Latency: ${(totalMicros / iterations).toStringAsFixed(2)} µs\n');

  // 2. THROUGHPUT
  print('2. Running Throughput Test (10k events)...');
  final throughputCompleter = Completer<void>();
  var processed = 0;
  final swThroughput = Stopwatch()..start();

  final subT = bloc.stream.listen((_) {
    processed++;
    if (processed == 10000) {
      throughputCompleter.complete();
    }
  });

  for (var i = 0; i < 10000; i++) {
    bloc.add(RunEvent(i));
  }
  await throughputCompleter.future.timeout(const Duration(seconds: 5));
  swThroughput.stop();
  print(
    '   Speed: ${(10000 / (swThroughput.elapsedMilliseconds / 1000)).toStringAsFixed(0)} events/sec\n',
  );

  // 3. MEMORY FOOTPRINT
  print('3. MEMORY FOOTPRINT (20k flood):');
  final initialMem = ProcessInfo.currentRss / 1024 / 1024;
  for (var i = 0; i < 20000; i++) {
    bloc.add(RunEvent(i));
  }
  final peakMem = ProcessInfo.currentRss / 1024 / 1024;
  print('   Overhead for 20k EventCancelTokens: ${(peakMem - initialMem).toStringAsFixed(2)} MB\n');

  await sub.cancel();
  await subT.cancel();
  await bloc.close();
}
