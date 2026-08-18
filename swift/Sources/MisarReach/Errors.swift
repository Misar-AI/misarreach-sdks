import Foundation

/// Errors thrown by ``MisarReachClient``.
public enum MisarReachError: Error, CustomStringConvertible {

    /// The API returned a non-2xx HTTP response (other than a rate limit).
    ///
    /// - Parameters:
    ///   - status:  HTTP status code (401, 403, 404, 4xx, 5xx …).
    ///   - message: Human-readable description from the API `error` field.
    ///   - code:    Optional machine-readable error code.
    case apiError(status: Int, message: String, code: String?)

    /// HTTP 429 — the request was rate-limited or requires an upgrade.
    ///
    /// - Parameters:
    ///   - message:       Human-readable description.
    ///   - balance:       Remaining wallet credit balance, when supplied.
    ///   - freeRemaining: Remaining free-tier allowance, when supplied.
    ///   - upgrade:       `true` when the caller must upgrade their plan.
    case rateLimit(message: String, balance: Double?, freeRemaining: Int?, upgrade: Bool)

    /// A counted plan cap was hit.
    ///
    /// MisarReach answers 402 with `upgrade: true` when a cap is reached and
    /// names the offending counter. Retrying cannot help until the cap resets
    /// or the plan changes.
    ///
    /// Distinct from the 503 `retry: true` the server sends when it could not
    /// *check* the quota: that one is retried, so "we do not know" is never
    /// mistaken for "you are over your limit".
    case upgradeRequired(
        status: Int,
        message: String,
        feature: String?,
        limit: Int?,
        current: Int?,
        upgradeURL: String?
    )

    /// A network-level error prevented the request from completing, or the
    /// maximum number of retries was exhausted.
    case networkError(message: String)

    /// HTTP status carried by the error (0 for network errors).
    public var status: Int {
        switch self {
        case .apiError(let status, _, _): return status
        case .rateLimit:                  return 429
        case .upgradeRequired(let status, _, _, _, _, _): return status
        case .networkError:               return 0
        }
    }

    public var description: String {
        switch self {
        case .apiError(let status, let message, let code):
            return "MisarReachError.apiError(\(status)\(code.map { ", \($0)" } ?? "")): \(message)"
        case .upgradeRequired(let status, let message, let feature, _, _, let url):
            var out = "MisarReachError.upgradeRequired(\(status)): \(message)"
            if let feature { out += " [feature=\(feature)]" }
            if let url { out += " [upgrade=\(url)]" }
            return out
        case .rateLimit(let message, let balance, let freeRemaining, let upgrade):
            let balanceStr = balance.map { "\($0)" } ?? "nil"
            let freeStr = freeRemaining.map { "\($0)" } ?? "nil"
            return "MisarReachError.rateLimit(upgrade=\(upgrade), balance=\(balanceStr), freeRemaining=\(freeStr)): \(message)"
        case .networkError(let message):
            return "MisarReachError.networkError: \(message)"
        }
    }
}

/// A single Server-Sent Event emitted by a streaming endpoint.
public struct MisarReachStreamEvent {
    /// Event name (`progress`, `complete`, `error`, or `message` when unnamed).
    public let event: String
    /// Decoded JSON payload of the event, when parseable.
    public let data: [String: Any]
    /// Raw `data:` text of the event.
    public let raw: String

    /// The synthesised memberwise initialiser is `internal`, so without this a
    /// caller outside the module could read a `MisarReachStreamEvent` but never
    /// construct one — no test double, no replayed fixture.
    public init(event: String, data: [String: Any], raw: String) {
        self.event = event
        self.data = data
        self.raw = raw
    }
}

public extension MisarReachError {
    /// The billing URL to send the user to, when this is a plan refusal.
    var upgradeURL: String? {
        if case let .upgradeRequired(_, _, _, _, _, url) = self { return url }
        return nil
    }
}
