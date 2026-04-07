import 'package:meta/meta_meta.dart';

/// Marks a method as an error mapper for a specific event type.
///
/// Use this annotation on methods that handle errors for particular events.
/// The annotated method will be automatically wired up via code generation.
///
/// Example:
/// ```dart
/// @ErrorStateFor<LoadUserEvent>()
/// UserState? onLoadUserError(Object error, StackTrace stack, LoadUserEvent event) {
///   return UserError('Failed to load user ${event.id}');
/// }
/// ```
@Target({TargetKind.method})
class ErrorStateFor<T> {
  const ErrorStateFor();
}

/// Marks a BLoC class as eligible for error handler code generation.
///
/// Apply this annotation to any BLoC class that uses `BlocErrorControlMixin`
/// to enable automatic generation of error mapper wiring.
///
/// Example:
/// ```dart
/// import 'package:bloc_error_control/annotations.dart';
///
/// @BlocErrorControl()
/// class UserBloc extends Bloc<UserEvent, UserState>
///     with BlocErrorControlMixin<UserEvent, UserState> {
///   // ...
/// }
/// ```
@Target({TargetKind.classType})
class BlocErrorControl {
  /// Creates an annotation for a BLoC class.
  const BlocErrorControl();
}

/// Constant instance of [BlocErrorControl] for cleaner annotation syntax.
///
/// Use this constant instead of instantiating the class directly:
/// ```dart
/// @blocErrorControl
/// class UserBloc extends ... { ... }
/// ```
const blocErrorControl = BlocErrorControl();
