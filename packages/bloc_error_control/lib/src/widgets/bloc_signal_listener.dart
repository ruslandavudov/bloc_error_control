import 'dart:async';

import 'package:bloc_error_control/src/interfaces/i_bloc_control.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Слушает сигналы от блока [B] порожденные событием типа [T].
class BlocSignalListener<B extends IBlocControl<Object?, Object?>, T> extends StatefulWidget {
  final Widget child;
  final void Function(BuildContext context, Object signal) onSignal;

  const BlocSignalListener({
    required this.child,
    required this.onSignal,
    super.key,
  });

  @override
  State<BlocSignalListener<B, T>> createState() => _BlocSignalListenerState<B, T>();
}

class _BlocSignalListenerState<B extends IBlocControl<Object?, Object?>, T>
    extends State<BlocSignalListener<B, T>> {
  StreamSubscription? _subscription;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void didUpdateWidget(BlocSignalListener<B, T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    _subscribe();
  }

  void _subscribe() {
    _subscription?.cancel();
    final bloc = context.read<B>();
    _subscription = bloc.signalsFor<T>().listen((signal) {
      if (mounted) {
        widget.onSignal(context, signal);
      }
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
