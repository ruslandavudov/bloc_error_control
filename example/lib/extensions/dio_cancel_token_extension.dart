import 'dart:async';

import 'package:bloc_error_control/bloc_error_control.dart';
import 'package:dio/dio.dart';

extension DioCancelTokenX on ICancelToken {
  /// Converts [ICancelToken] to Dio's [CancelToken].
  ///
  /// Automatically synchronizes the cancellation state and propagates the
  /// cancellation reason when available.
  ///
  /// This extension is useful when you need to pass the mixin's cancellation
  /// token to Dio HTTP requests while maintaining automatic cancellation
  /// capabilities.
  ///
  /// Example:
  /// ```dart
  /// Future<void> _onFetchData(FetchDataEvent event, Emitter<AppState> emit) async {
  ///   emit(AppLoading());
  ///   final response = await dio.get(
  ///     'https://api.example.com/data',
  ///     cancelToken: contextToken.toDio(),
  ///   );
  ///   emit(AppLoaded(response.data));
  /// }
  /// ```
  CancelToken toDio() {
    final dioToken = CancelToken();

    // If already cancelled, return an already cancelled Dio token immediately
    if (isCancelled) {
      _safeCancel(dioToken);
      return dioToken;
    }

    // Listen for future cancellation and propagate to Dio token.
    // Using unawaited because we don't need to wait for this operation.
    unawaited(
      whenCancel
          .then((_) {
            _safeCancel(dioToken);
          })
          .catchError((_) {
            // Error ignored — token already cancelled or resources already disposed.
          }),
    );

    return dioToken;
  }

  /// Safely cancels the Dio token if it hasn't been cancelled already.
  ///
  /// Attempts to extract the cancellation reason from [EventCancelToken]
  /// and passes it to Dio for debugging purposes.
  void _safeCancel(CancelToken dioToken) {
    if (!dioToken.isCancelled) {
      // Try to get the cancellation reason from EventCancelToken implementation
      final dynamic reason = this is EventCancelToken ? (this as EventCancelToken).reason : null;
      dioToken.cancel(reason);
    }
  }
}
