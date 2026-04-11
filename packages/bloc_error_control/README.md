# 🛡️ Bloc Error Control

**An advanced error handling and event lifecycle management solution for Flutter applications built
with BLoC. The package transforms chaotic asynchronous exceptions into structured states while
preventing memory leaks and resource waste.**

## 🎯 When to Use This Package

✅ **Use it if:**
- You have a large project (50+ events)
- You're tired of try-catch boilerplate
- You need automatic request cancellation
- You're ready to learn about Zones

❌ **Don't use it if:**
- You have a small project (less than 10 events)
- You're not familiar with Zones
- You find it easier to write try-catch

---

## 🎯 Why do you need this?

### The Problem: Typical BLoC code

```dart
on<LoadUser>((event, emit) async {
  emit(UserLoading());
  try {
    final user = await userRepository.getUser(event.id);
    emit(UserLoaded(user));
  } on SocketException {
    emit(UserError('No internet connection'));
  } on ApiException catch (e) {
    emit(UserError(e.message));
  } catch (e, stack) {
    logger.error('Unexpected', error: e, stackTrace: stack);
    emit(UserError('Something went wrong'));
  }
});
```

**Problems:**

- 80% of the code is error handling
- Easy to forget handling an exception
- No automatic cancellation of "hanging" requests

The Solution: Your code becomes clean

```dart
on<LoadUser>((event, emit) async {
  emit(UserLoading());
  final user = await userRepository.getUser(event.id, token: contextToken);
  emit(UserLoaded(user));
});
```

**That's it!** No try-catch. **Errors are handled centrally.**.

## 📦 Features

| Feature                              | Description                                                      |
|:-------------------------------------|:-----------------------------------------------------------------|
| **🚫 No try-catch**                  | Event handlers contain only business logic                       |
| **🎯 Centralized error handling**    | `mapErrorToState` — one method for all errors                    |
| **🔌 Auto-cancellation of requests** | `contextToken` automatically cancels requests on repeated events |
| **🧹 Cleanup on `close()`**          | All active requests are cancelled when the bloc is closed        |
| **📝 Flexible logging**              | Plug any logger (Sentry, Firebase, custom)                       |
| **⚡️ Works with any transformers**   | `sequential()`, `restartable()`, `debounce()` etc.               |
| **🧬 Optional code generation**      | Minimal boilerplate through annotations                          |

## 🚀 Quick start

```dart
class UserBloc extends Bloc<UserEvent, UserState>
    with BlocErrorControlMixin<UserEvent, UserState> {

  UserBloc() : super(UserInitial()) {
    on<LoadUserEvent>(_onLoadUser);
  }

  @override
  UserState? mapErrorToState(Object error, StackTrace stack, UserEvent event) {
    // All errors from handlers go here
    if (error is SocketException) {
      return UserError('No internet connection');
    }
    return UserError('Something went wrong');
  }

  Future<void> _onLoadUser(LoadUserEvent event, Emitter<UserState> emit) async {
    emit(UserLoading());
    final user = await userRepository.getUser(event.id);
    emit(UserLoaded(user));
  }
}
```

## ⚡️ Signals (Side Effects)

**Signals** are a mechanism for transmitting one-time events from `BLoC` to `UI` (showing `Snackbar`, `Toast`, 
navigation, or triggering an animation).

### What problem does this solve?
In standard BLoC, to display an error notification, developers often add an `error` field to the State.

**This leads to several problems**:

- **Sticky State**: When the screen rebuilds (e.g., on rotation), the Snackbar appears again because the error is still present in the state.
- **State Pollution**: The state should describe **what is on the screen**, not **what happened once**.

**Signals operate in a parallel stream**: they are not persisted in the state, are delivered once, and are automatically bound to the event context.

### Usage in BLoC

To send a signal, use the `emitSignal()` method.

You can also configure automatic transformation of errors into signals via `mapErrorToSignal`.

```dart
class UserBloc extends Bloc<UserEvent, UserState> with BlocErrorControlMixin<UserEvent, UserState> {
  UserBloc() : super(UserInitial()) {
    on<UpdateProfileEvent>((event, emit) async {
      await repo.updateUser(event.user);
      // Manually send a success signal
      emitSignal('Profile updated successfully!');
    });
  }
  
  @override
  Object? mapErrorToSignal(Object error, StackTrace stack, UserEvent? event) {
    // If an error occurs while liking a post — don't change the state,
    // just notify the user via a signal
    if (event is LikePostEvent) {
      return 'Failed to like the post. Please try again later.';
    }
    return null;
  }
}
```

### Handling in UI (BlocSignalListener)

To listen for signals, use the dedicated `BlocSignalListener` widget. 
Thanks to type support, you can listen to signals from the entire bloc or from specific events.

```dart
// Listen only to signals from the UpdateProfileEvent
BlocSignalListener<UserBloc, UpdateProfileEvent>(
  onSignal: (context, signal) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(signal.toString())),
    );
  },
  child: ProfileScreen(),
)
```

### Advantages of signals in this library
- **Context-Aware**: Thanks to the Zone API, each signal "knows" which event it was sent from. 
  This allows filtering notifications in the UI.
- **Auto-cancellation**: If an event is cancelled (e.g., via restartable), 
  any signals that haven't been sent from its asynchronous code will be ignored.
- **Type Safety**: You can pass any objects as signals (strings, sealed classes, DTOs).

## Support request cancellation (optional)

```dart
Future<void> _onSearch(SearchEvent event, Emitter<SearchState> emit) async {
  emit(SearchLoading());
  final results = await searchRepository.search(
    event.query,
    token: contextToken, // ← automatic cancellation
  );
  emit(SearchLoaded(results));
}
```

## 🧬 Code generation (optional)

If you don't want to write `if (event is LoadUserEvent`) in `mapErrorToState`,
or override the `getErrorMapperForEvent` method:

- Add annotation to the class

```dart
import 'package:bloc_error_control/annotations.dart';

@BlocErrorControl() // ← add this
class UserBloc extends Bloc<UserEvent, UserState>
    with BlocErrorControlMixin<UserEvent, UserState> {
  // ...
}
```

- Add mapper methods with annotation

```dart
@ErrorStateFor<LoadUserEvent>()
UserState? onLoadUserError(Object error, StackTrace stack, LoadUserEvent event) {
  return UserError('Failed to load user ${event.id}');
}

@ErrorStateFor<UpdateUserEvent>()
UserState? onUpdateUserError(Object error, StackTrace stack, UpdateUserEvent event) {
  return UserError('Update failed');
}
```

- Run generation

```bash
dart run build_runner build --delete-conflicting-outputs
```

## 📊 Performance

| Metric                 | Result           | Description                                            |
|:-----------------------|:-----------------|:-------------------------------------------------------|
| **Latency**            | **~49.4 µs**     | Delay from `add(event)` to state emission              |
| **Throughput**         | **~69,000 ev/s** | Maximum event processing capacity per second           |
| **Memory Footprint**   | **0.02 MB**      | Additional weight of 20,000 active zones/tokens in RAM |
| **`throwIfCancelled`** | **~0.006 µs**    | Cost of a single token check inside a loop             |

## 🎯 How it works (briefly)

1. Each event runs in its own **Zone**
2. A unique **ICancelToken** is created in the zone
3. If an error occurs, the mixin:

- Finds the appropriate mapper (local → event-specific → global)
- Transforms the error into a state
- Logs the error

4. On repeated events — **the previous request is cancelled**
5. When the bloc is closed — **all active requests are cancelled**

## 🧪 Test Coverage

The package has **complete code coverage** with tests, including all edge cases and asynchronous scenarios.

| Component | Coverage |
|-----------|----------|
| **mixins/** | 100% |
| **models/** | 100% |
| **annotations/** | 100% |
| **exceptions/** | 100% |
| **Total** | **100%** |

### Running Tests

```bash
flutter test test/bloc_error_control_mixin/unit/bloc_error_control_test.dart  
```

**Branch Coverage**
- The core mixin logic has 84.6% branch coverage

**Generating Coverage Report:**
```bash
flutter test --coverage
genhtml coverage/lcov.info -o coverage/html
open coverage/html/index.html 
```

## 🔧 API Reference

| Method                                                            | Description          |
|:------------------------------------------------------------------|:---------------------|
| **`S? mapErrorToState(Object error, StackTrace stack, E event)`** | Global error handler |

## Optional methods

| Method                                                    | Description                            |
|:----------------------------------------------------------|:---------------------------------------|
| **`set logger(ErrorLogger logger)`**                      | Plug your own logger                   |
| **`bool isGlobalSilent(Object error, StackTrace stack)`** | Filter "silent" errors                 |
| **`ICancelToken get contextToken`**                       | Cancellation token for requests        |
| **`void cancelTokensByEventType<T>()`**                   | Cancel all requests of a specific type |
| **`List<Map<String, dynamic>> getActiveTokensInfo()`**    | Diagnostics of active requests         |

## on() parameters

| Parameter         | Description                                               |
|:------------------|:----------------------------------------------------------|
| **`transformer`** | Event transformer (`sequential()`, `restartable()`, etc.) |
| **`timeout`**     | Event timeout (default 30 sec)                            |

## ⚠️ Requirements

- Flutter >= 3.0.0
- flutter_bloc >= 8.0.0
- Dart >= 3.0.0

---

## ✨ Key features

* **🛡️ Zone-based error isolation**: Catches "wild" asynchronous errors (in timers, microtasks) that
  would otherwise crash the app.
* **🔌 Universal Token (`contextToken`):** Automatic cancellation management (CancelToken) for
  network requests and heavy computations.
* **🚀 Near-zero overhead:** Processing one event takes less than **1 microsecond**.
* **🧹 State cleanliness:** Protection against "Zombie Emits" (attempts to change state after the
  event or Bloc has been closed).
* **🤖 Optional code generation:** Automatic creation of error mappers through annotations.
* **🔕 Silent errors:** Built-in filtering of cancellations (e.g., Dio cancel) that shouldn't change
  the UI.

---

## ⚙️ Installation

Add dependencies to your `pubspec.yaml`:

```yaml
dependencies:
  bloc_error_control: ^1.2.0

dev_dependencies:
  bloc_error_control_generator: ^1.2.0
  build_runner: ^2.10.0
```

## 🔌 Example: Dio Integration for ICancelToken

For convenient integration with the Dio HTTP client, the package provides the `DioCancelTokenX` extension, which converts `ICancelToken` to Dio's `CancelToken`.

**Complete extension code:**
```dart
extension DioCancelTokenX on ICancelToken {
  /// Converts [ICancelToken] to Dio's [CancelToken].
  CancelToken toDio() {
    final dioToken = CancelToken();

    if (isCancelled) {
      _safeCancel(dioToken);
      return dioToken;
    }

    unawaited(
      whenCancel.then((_) {
        _safeCancel(dioToken);
      }).catchError((_) {
        // Error ignored
      }),
    );

    return dioToken;
  }

  void _safeCancel(CancelToken dioToken) {
    if (!dioToken.isCancelled) {
      final reason = this is EventCancelToken ? (this as EventCancelToken).reason : null;
      dioToken.cancel(reason);
    }
  }
}
```

- Usage
```dart
class UserBloc extends Bloc<UserEvent, UserState>
    with BlocErrorControlMixin<UserEvent, UserState> {
  
  final Dio _dio = Dio();

  Future<void> _onLoadUser(LoadUserEvent event, Emitter<UserState> emit) async {
    emit(UserLoading());
    
    final response = await _dio.get(
      'https://api.example.com/users/${event.id}',
      cancelToken: contextToken.toDio(), // ← conversion
    );
    
    emit(UserLoaded(response.data));
  }
}
```

**The extension automatically:**
- Synchronizes the cancellation state between `ICancelToken` and Dio's `CancelToken`
- Propagates the cancellation reason for debugging purposes
- Safely handles cases where the token is already cancelled


## 📄 License

MIT © 2025

This software is distributed under the MIT license.
