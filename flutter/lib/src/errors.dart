/// Base error for any non-2xx MisarReach API response.
class MisarReachException implements Exception {
  final int statusCode;
  final String message;
  final String? code;

  /// Decoded JSON error body, when available.
  final Map<String, dynamic>? body;

  const MisarReachException(this.statusCode, this.message, {this.code, this.body});

  @override
  String toString() =>
      'MisarReachException($statusCode${code != null ? ', $code' : ''}): $message';
}

/// 401 / 403 — missing, invalid, or insufficiently-scoped `mrk_` key.
class MisarReachAuthException extends MisarReachException {
  const MisarReachAuthException(super.statusCode, super.message, {super.body})
      : super(code: 'unauthorized');
}

/// 404 — resource not found.
class MisarReachNotFoundException extends MisarReachException {
  const MisarReachNotFoundException(String message, {Map<String, dynamic>? body})
      : super(404, message, code: 'not_found', body: body);
}

/// 429 — rate limited. [retryAfter] carries seconds to wait when provided.
class MisarReachRateLimitException extends MisarReachException {
  final int? retryAfter;
  final num? balance;
  final num? freeRemaining;

  const MisarReachRateLimitException(
    String message, {
    this.retryAfter,
    this.balance,
    this.freeRemaining,
    Map<String, dynamic>? body,
  }) : super(429, message, code: 'rate_limit', body: body);
}

/// 429 with `upgrade: true` — the workspace plan must be upgraded to proceed.
class MisarReachUpgradeRequiredException extends MisarReachException {
  const MisarReachUpgradeRequiredException(String message,
      {Map<String, dynamic>? body})
      : super(429, message, code: 'upgrade_required', body: body);
}

/// Connectivity failure — no HTTP response received.
class MisarReachNetworkException extends MisarReachException {
  const MisarReachNetworkException(String message)
      : super(0, message, code: 'network_error');
}
