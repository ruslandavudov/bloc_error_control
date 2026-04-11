import 'package:bloc_error_control/src/interfaces/i_cancel_token.dart';
import 'package:bloc_error_control/src/mixins/bloc_error_control_mixin.dart';
import 'package:bloc_error_control/src/widgets/bloc_signal_listener.dart';
import 'package:meta/meta.dart';

/// BLoC lifecycle and side effect management interface.
///
/// [IBlocControl] combines three critical functions:
/// 1. **Error Handling**: Separation into states (State) and notifications (Signal).
/// 2. **Async Management**: Access to cancellation tokens [ICancelToken].
/// 3. **Diagnostics**: Real-time monitoring of active processes.
///
/// This contract guarantees that every BLoC event executes within a protected
/// context (Zone API), preventing resource leaks and "dirty" state.
///
/// Implemented by the [BlocErrorControlMixin] mixin.
///
/// Usage example:
/// ```dart
/// class MyBloc extends Bloc<MyEvent, MyState>
///     with BlocErrorControlMixin<MyEvent, MyState> {
///   // Implement mapErrorToState and optionally mapErrorToSignal
/// }
/// ```
abstract interface class IBlocControl<E extends Object, S> {
  /// **Global error mapper.**
  ///
  /// Must be implemented in your Bloc. Define common error-to-state conversion
  /// logic here, e.g., transforming `SocketException` into an offline state.
  ///
  /// This method is called when no local or generated mapper handles the error.
  @protected
  @mustBeOverridden
  S? mapErrorToState(Object error, StackTrace s, E event);

  /// Transforms an exception into a Signal (one-time UI event).
  ///
  /// This method is the key tool for implementing informational messages.
  /// Unlike [mapErrorToState], it does not change the screen state but sends
  /// an object to a parallel signal stream.
  ///
  /// **Why this is needed:**
  /// * **Separation of concerns:** Critical errors (no access, 404) are sent
  ///   to State via [mapErrorToState], while side effects (like error on like,
  ///   auto-save failure, etc.) go to Signal.
  /// * **UI purity:** Eliminates "sticky" errors in state that require manual
  ///   clearing after showing a Snackbar.
  /// * **Context-aware:** Thanks to the [event] parameter, you can react
  ///   differently to the same error depending on which action caused it.
  ///
  /// **Error handling order:**
  /// 1. [mapErrorToState] — attempts to convert error to a state
  /// 2. If returns `null`, [mapErrorToSignal] is called
  /// 3. If also returns `null` — error is only logged
  ///
  /// **Usage example:**
  /// ```dart
  /// @override
  /// Object? mapErrorToSignal(Object error, StackTrace stack, UserEvent? event) {
  ///   if (error is NetworkException) {
  ///     // If a background request failed — just notify the user
  ///     if (event is LikePostEvent || event is UpdateSettingsEvent) {
  ///       return 'Connection issue. Action will be retried later';
  ///     }
  ///   }
  ///   return null; // Otherwise no signal is sent
  /// }
  /// ```
  ///
  /// **On the UI side, signals are handled via [BlocSignalListener]:**
  /// ```dart
  /// BlocSignalListener<MyBloc, MyEvent>(
  ///   onSignal: (context, signal) {
  ///     ScaffoldMessenger.showSnackBar(
  ///       SnackBar(content: Text(signal.toString())),
  ///     );
  ///   },
  ///   child: MyWidget(),
  /// )
  /// ```
  ///
  /// **Type safety recommendation:**
  /// For strict signal typing, use sealed classes:
  /// ```dart
  /// sealed class AppSignal {
  ///   factory AppSignal.showMessage(String text) = ShowMessageSignal;
  ///   factory AppSignal.navigateTo(String route) = NavigateToSignal;
  /// }
  /// ```
  @protected
  @visibleForTesting
  Object? mapErrorToSignal(Object error, StackTrace stackTrace, E? event) => null;

  /// Returns the [ICancelToken] for the currently executing event.
  ///
  /// **Always pass this token to async operations:**
  /// `repo.getData(token: contextToken)`
  ///
  /// The token is automatically cancelled when:
  /// - The event handler completes
  /// - An exception occurs
  /// - A new event of the same type is dispatched (with `restartable`)
  /// - The BLoC is closed
  @protected
  @visibleForTesting
  ICancelToken get contextToken;

  /// Sends a signal (one-time event) to the signal stream.
  ///
  /// Signals are intended for UI side effects: notifications, navigation,
  /// analytics. Unlike state, a signal is not persisted and does not
  /// overwrite previous values.
  ///
  /// **Example:**
  /// ```dart
  /// on<SaveEvent>((event, emit) async {
  ///   await repository.save(event.data);
  ///   emitSignal('Data saved'); // UI will show a SnackBar
  /// });
  /// ```
  @protected
  @visibleForTesting
  void emitSignal(Object signal);

  /// Returns a filtered stream of signals for a specific event type [T].
  ///
  /// - If [T] is a concrete event type (e.g., `LoadUserEvent`), only signals
  ///   sent from that event's handler will be received.
  /// - If [T] matches the base type [E], **all** signals from the bloc are broadcast.
  ///
  /// This allows different widgets to subscribe to signals from different events.
  Stream<Object> signalsFor<T extends E>();

  /// Cancels all tokens associated with events of a specific type.
  @protected
  @visibleForTesting
  void cancelTokensByEventType<T extends E>();

  /// Cancels the token for a specific event instance.
  @protected
  @visibleForTesting
  bool cancelTokenForEvent(E event);

  /// Returns diagnostic information about active tokens.
  ///
  /// Useful for debugging hanging requests or monitoring resource usage.
  @protected
  @visibleForTesting
  List<Map<String, dynamic>> getActiveTokensInfo();

  /// Checks whether an active token exists for the given event.
  @protected
  @visibleForTesting
  bool hasActiveTokenForEvent(E event);
}
