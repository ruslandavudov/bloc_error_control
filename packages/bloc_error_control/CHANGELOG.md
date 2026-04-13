## 1.2.2

- Clarified error handling and signal semantics in the docs.
- Updated tests for observer behavior and parallel state/signal handling.
- Fixed analyzer configuration for the package and example.

## 1.2.0
- Added Signals (Side Effects) support: a parallel stream for one-time events (Snackbars, Navigation, etc.)
- Added IBlocControl interface: centralized management of signals, tokens, and diagnostics
- Added mapErrorToSignal: a new declarative way to handle transient errors without changing the business state
- Added BlocSignalListener widget: context-aware listener for targeted signal handling
- Improved Zone-based infrastructure: signals are now linked to specific events

## 1.1.2
- Changed ErrorStateFor annotation - now generic
- Fixed dependencies
- Updated example project
- Updated README

## 1.1.1
- fixing dependencies

## 1.1.0
- Initial release of split packages.
- Support for BLoC 9.0.

## 1.0.1
- Updated dependencies to support flutter_bloc 9.x
- flutter_bloc: '>=8.1.6 <10.0.0'
- bloc: '>=8.0.0 <10.0.0'

## 1.0.0
- Initial release
- Added BlocErrorControlMixin with Zone-based error isolation
- Added ICancelToken for automatic request cancellation
- Added optional code generation with @BlocErrorControl and @ErrorStateFor
- Added comprehensive tests and benchmarks
