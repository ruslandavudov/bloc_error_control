import 'package:bloc_error_control/bloc_error_control.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'bloc/user_bloc.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BlocErrorControlMixin-Demo',
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple)),
      home: BlocProvider(lazy: false, create: (context) => UserBloc(), child: const MyHomePage()),
    );
  }
}

class MyHomePage extends StatelessWidget {
  const MyHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final buttonStyle = ButtonStyle(
      backgroundColor: WidgetStateProperty.all(Colors.blueAccent),
      foregroundColor: WidgetStateProperty.all(Colors.white),
    );
    return Scaffold(
      body: BlocBuilder<UserBloc, UserState>(
        builder: (context, state) {
          final child = switch (state) {
            UserLoaded() => Text(state.name),
            UserError() => Text(state.message),
            _ => const Text('loading...'),
          };

          return BlocSignalListener<UserBloc, LoadUser2Event>(
            onSignal: (context, signal) {
              debugPrint('signal: $signal');
            },
            child: Center(child: child),
          );
        },
      ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            style: buttonStyle,
            onPressed: () {
              context.read<UserBloc>().add(const LoadUser1Event('User1'));
            },
            child: const Text('LoadUser1Event'),
          ),
          TextButton(
            style: buttonStyle,
            onPressed: () {
              context.read<UserBloc>().add(const LoadUser2Event('User2'));
            },
            child: const Text('LoadUser2Event'),
          ),
          TextButton(
            style: buttonStyle,
            onPressed: () {
              context.read<UserBloc>().add(const LoadUser3Event('User3'));
            },
            child: const Text('LoadUser3Event'),
          ),
        ],
      ),
    );
  }
}
