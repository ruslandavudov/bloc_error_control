import 'dart:async';

import 'package:bloc_error_control/bloc_error_control.dart';

part 'user_bloc.error.g.dart';

sealed class UserEvent {
  final String id;

  const UserEvent(this.id);
}

final class LoadUser1Event extends UserEvent {
  const LoadUser1Event(super.id);
}

final class LoadUser2Event extends UserEvent {
  const LoadUser2Event(super.id);
}

final class LoadUser3Event extends UserEvent {
  const LoadUser3Event(super.id);
}

sealed class UserState {}

class UserInitial extends UserState {}

class UserLoading extends UserState {}

class UserLoaded extends UserState {
  final String name;

  UserLoaded(this.name);
}

class UserError extends UserState {
  final String message;

  UserError(this.message);
}

@blocErrorHandler
class UserBloc extends Bloc<UserEvent, UserState> with _$UserBlocErrorMapper<UserEvent, UserState> {
  UserBloc() : super(UserInitial()) {
    on<UserEvent>(
      (event, emit) => switch (event) {
        LoadUser1Event() => _onLoadUser1Event(event, emit),
        LoadUser2Event() => _onLoadUser2Event(event, emit),
        LoadUser3Event() => _onLoadUser3Event(event, emit),
      },
    );
  }

  @override
  UserState? mapErrorToState(Object error, StackTrace stack, UserEvent event) {
    final message = '[${event.runtimeType}] Global error';
    debugPrint(message);
    return UserError(message);
  }

  Future<void> _onLoadUser1Event(LoadUser1Event event, Emitter<UserState> emit) async {
    emit(UserLoading());
    throw Exception('[LoadUser1Event] Test error');
  }

  Future<void> _onLoadUser2Event(LoadUser2Event event, Emitter<UserState> emit) async {
    emit(UserLoading());
    throw Exception('[LoadUser2Event] Test error');
  }

  Future<void> _onLoadUser3Event(LoadUser3Event event, Emitter<UserState> emit) async {
    emit(UserLoading());
    throw Exception('[LoadUser3Event] Test error');
  }

  @ErrorStateFor(LoadUser2Event)
  @ErrorStateFor(LoadUser3Event)
  UserState? onLoadUserError(Object error, StackTrace stack, UserEvent event) {
    final message = '[${event.runtimeType}] Local error';
    debugPrint(message);
    return UserError(message);
  }
}
