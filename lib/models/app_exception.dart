/// An error whose [message] is safe and meaningful to show to the user.
class AppException implements Exception {
  const AppException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Thrown internally when the user cancels a running flow.
class FlowCancelledException implements Exception {
  const FlowCancelledException();
}
