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
