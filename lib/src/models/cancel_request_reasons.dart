/// Reasons for request cancellation.
///
/// Used to provide context when cancelling operations, useful for debugging
/// and logging to understand why a request was terminated.
enum CancelRequestReasons {
  /// Request was cancelled manually by user action or programmatic call.
  manual,

  /// Request was cancelled automatically by the system (e.g., on bloc close).
  auto,

  /// Request was cancelled for other unspecified reasons.
  other,
}
