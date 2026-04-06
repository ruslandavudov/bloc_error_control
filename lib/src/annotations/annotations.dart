import 'package:meta/meta_meta.dart';

/// Marks a method as an error mapper for a specific event type.
///
/// Use this annotation on methods that handle errors for particular events.
/// The annotated method will be automatically wired up via code generation.
///
/// Example:
/// ```dart
/// @ErrorStateFor(LoadUserEvent)
/// UserState? onLoadUserError(Object error, StackTrace stack, LoadUserEvent event) {
///   return UserError('Failed to load user ${event.id}');
/// }
/// ```
@Target({TargetKind.method})
class ErrorStateFor {
  /// The event type this mapper handles.
  final Type eventType;

  /// Creates an annotation for an error mapper method.
  const ErrorStateFor(this.eventType);
}

/// Marks a BLoC class as eligible for error handler code generation.
///
/// Apply this annotation to any BLoC class that uses `BlocErrorHandlerMixin`
/// to enable automatic generation of error mapper wiring.
///
/// Example:
/// ```dart
/// import 'package:bloc_error_control/annotations.dart';
///
/// @BlocErrorHandler()
/// class UserBloc extends Bloc<UserEvent, UserState>
///     with BlocErrorHandlerMixin<UserEvent, UserState> {
///   // ...
/// }
/// ```
@Target({TargetKind.classType})
class BlocErrorHandler {
  /// Creates an annotation for a BLoC class.
  const BlocErrorHandler();
}

/// Constant instance of [BlocErrorHandler] for cleaner annotation syntax.
///
/// Use this constant instead of instantiating the class directly:
/// ```dart
/// @blocErrorHandler
/// class UserBloc extends ... { ... }
/// ```
const blocErrorHandler = BlocErrorHandler();
