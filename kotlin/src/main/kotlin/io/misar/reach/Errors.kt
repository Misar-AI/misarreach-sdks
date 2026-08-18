package io.misar.reach

/**
 * Thrown when the MisarReach API returns a non-2xx HTTP response.
 *
 * The API emits a standard error envelope
 * `{ "error": { "code": "...", "message": "..." } }`; the extracted message is
 * exposed via [message] and the HTTP status via [status].
 *
 * @property status HTTP status code returned by the server.
 */
open class MisarReachException(
    val status: Int,
    message: String,
) : Exception("MisarReachException($status): $message")

/**
 * Thrown when a network-level error prevents the request from completing
 * (e.g. DNS failure, connection refused, timeout) or when the maximum number of
 * retries is exhausted.
 */
class MisarReachNetworkException(message: String) : MisarReachException(0, message)

/**
 * Thrown when a counted plan cap is hit.
 *
 * MisarReach answers 402 with `upgrade: true` when a cap is reached — searches,
 * results, autopilot runs, deals, seats, channels — and names the offending
 * counter. Retrying cannot help until the cap resets or the plan changes.
 *
 * Distinct from the 503 `retry: true` the server sends when it could not
 * *check* the quota: that one is retried, so "we do not know" is never mistaken
 * for "you are over your limit".
 */
class UpgradeRequiredException(
    status: Int,
    message: String,
    /** The counter that was exhausted, e.g. `lead_searches`. */
    val feature: String? = null,
    /** The cap on the current plan. */
    val limit: Int? = null,
    /** Usage against that cap when the call was refused. */
    val current: Int? = null,
    /** Absolute URL to the billing page. */
    val upgradeUrl: String? = null,
) : MisarReachException(status, message)
