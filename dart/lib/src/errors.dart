/// Base error for any non-2xx MisarReach API response.
class MisarReachError implements Exception {
  final int status;
  final String message;
  final String? code;

  /// Decoded JSON error body, when available.
  final Map<String, dynamic>? body;

  const MisarReachError(this.status, this.message, {this.code, this.body});

  @override
  String toString() =>
      'MisarReachError($status${code != null ? ', $code' : ''}): $message';
}

/// 401 / 403 — missing, invalid, or insufficiently-scoped `mrk_` key.
class AuthError extends MisarReachError {
  const AuthError(super.status, super.message, {super.body})
      : super(code: 'unauthorized');
}

/// 404 — resource not found.
class NotFoundError extends MisarReachError {
  const NotFoundError(String message, {Map<String, dynamic>? body})
      : super(404, message, code: 'not_found', body: body);
}

/// 429 — rate limited. [retryAfter] carries seconds to wait when provided.
class RateLimitError extends MisarReachError {
  final int? retryAfter;
  final num? balance;
  final num? freeRemaining;

  const RateLimitError(
    String message, {
    this.retryAfter,
    this.balance,
    this.freeRemaining,
    Map<String, dynamic>? body,
  }) : super(429, message, code: 'rate_limit', body: body);
}

/// 429 with `upgrade: true` — the workspace plan must be upgraded to proceed.
class UpgradeRequiredError extends MisarReachError {
  const UpgradeRequiredError(String message, {Map<String, dynamic>? body})
      : super(429, message, code: 'upgrade_required', body: body);
}

/// Connectivity failure — no HTTP response received.
class MisarReachNetworkError extends MisarReachError {
  const MisarReachNetworkError(String message)
      : super(0, message, code: 'network_error');
}
