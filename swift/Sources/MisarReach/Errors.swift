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

    /// A network-level error prevented the request from completing, or the
    /// maximum number of retries was exhausted.
    case networkError(message: String)

    /// HTTP status carried by the error (0 for network errors).
    public var status: Int {
        switch self {
        case .apiError(let status, _, _): return status
        case .rateLimit:                  return 429
        case .networkError:               return 0
        }
    }

    public var description: String {
        switch self {
        case .apiError(let status, let message, let code):
            return "MisarReachError.apiError(\(status)\(code.map { ", \($0)" } ?? "")): \(message)"
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
}
