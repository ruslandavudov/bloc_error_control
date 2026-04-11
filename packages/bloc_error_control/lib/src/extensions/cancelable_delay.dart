import 'dart:async';

import 'package:bloc_error_control/src/exceptions/bloc_canceled_exception.dart';
import 'package:bloc_error_control/src/interfaces/i_cancel_token.dart';

extension CancelableDelay on ICancelToken {
  Future<void> delay(Duration duration) async {
    if (isCancelled) {
      throw BlocCanceledException();
    }

    final completer = Completer<void>();

    final timer = Timer(duration, () {
      if (!completer.isCompleted) {
        completer.complete();
      }
    });

    unawaited(
      whenCancel
          .then((_) {
            if (!completer.isCompleted) {
              timer.cancel();
              completer.completeError(BlocCanceledException());
            }
          })
          .catchError((_) {
            // Error ignored — token already cancelled or resources already disposed.
          }),
    );

    return completer.future;
  }
}
