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
/// A counted plan cap was hit.
///
/// MisarReach answers 402 with `upgrade: true` when a cap is reached and names
/// the offending counter. Retrying cannot help until the cap resets or the plan
/// changes.
///
/// Distinct from the 503 `retry: true` the server sends when it could not
/// *check* the quota: that one is retried, so "we do not know" is never
/// mistaken for "you are over your limit".
class UpgradeRequiredError extends MisarReachError {
  static const _appOrigin = 'https://misarreach.com';

  const UpgradeRequiredError(String message,
      {Map<String, dynamic>? body, int status = 402})
      : super(status, message, code: 'upgrade_required', body: body);

  /// The counter that was exhausted, e.g. `lead_searches`.
  String? get feature => body?['feature'] as String?;

  /// The cap on the current plan.
  int? get limit => (body?['limit'] as num?)?.toInt();

  /// Usage against that cap when the call was refused.
  int? get current => (body?['current'] as num?)?.toInt();

  /// Absolute URL to the billing page. The server sends an app-relative path.
  String? get upgradeUrl {
    final raw = body?['upgrade_url'] as String?;
    if (raw == null) return null;
    if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;
    return '$_appOrigin${raw.startsWith('/') ? raw : '/$raw'}';
  }
}

/// Connectivity failure — no HTTP response received.
class MisarReachNetworkError extends MisarReachError {
  const MisarReachNetworkError(String message)
      : super(0, message, code: 'network_error');
}
