import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking

/// swift-corelibs-foundation has no async `data(for:)` or `bytes(for:)`, so the
/// client would not build on Linux. Bridging the completion-handler API keeps
/// the SDK one implementation on every platform instead of two behind `#if`.
extension URLSession {
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            let task = dataTask(with: request) { data, response, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let data, let response {
                    continuation.resume(returning: (data, response))
                } else {
                    continuation.resume(throwing: URLError(.badServerResponse))
                }
            }
            task.resume()
        }
    }
}
#endif

// MARK: - Client

/// MisarReach API client — lead finder, CRM (deals + pipeline), multi-channel
/// outreach, autopilot, and sales-agent automation.
///
/// Authenticates with a `mrk_` API key (Bearer) against
/// `https://api.misar.io/reach/api`. All methods perform up to ``maxRetries``
/// attempts with exponential back-off on retryable HTTP statuses
/// (429, 500, 502, 503, 504); the final failure is surfaced as a typed
/// ``MisarReachError``.
public final class MisarReachClient {

    public let apiKey: String
    public let baseURL: String
    public let maxRetries: Int
    public let session: URLSession

    private static let retryableStatuses: Set<Int> = [429, 500, 502, 503, 504]

    public init(
        apiKey: String,
        baseURL: String = "https://api.misar.io/reach/api",
        maxRetries: Int = 3,
        session: URLSession = .shared
    ) {
        self.apiKey = apiKey
        let trimmed = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        self.baseURL = trimmed
        self.maxRetries = maxRetries
        self.session = session
    }

    // MARK: Core request

    internal func request(
        method: String,
        path: String,
        body: [String: Any]? = nil
    ) async throws -> [String: Any] {
        guard let url = URL(string: baseURL + path) else {
            throw MisarReachError.networkError(message: "Invalid URL: \(baseURL + path)")
        }

        var urlRequest = URLRequest(url: url, timeoutInterval: 30)
        urlRequest.httpMethod = method
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")

        if let body = body {
            urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        var lastError: Error?

        for attempt in 0..<maxRetries {
            if attempt > 0 {
                let delayNs = UInt64(500_000_000) * UInt64(1 << (attempt - 1))
                try await Task.sleep(nanoseconds: delayNs)
            }

            let data: Data
            let response: URLResponse
            do {
                (data, response) = try await session.data(for: urlRequest)
            } catch {
                lastError = error
                continue
            }

            guard let http = response as? HTTPURLResponse else {
                lastError = MisarReachError.networkError(message: "Non-HTTP response")
                continue
            }

            let status = http.statusCode

            if Self.retryableStatuses.contains(status) && attempt < maxRetries - 1 {
                lastError = MisarReachError.apiError(status: status, message: "retryable", code: nil)
                continue
            }

            if (200..<300).contains(status) {
                if data.isEmpty { return [:] }
                guard let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    return [:]
                }
                return parsed
            }

            throw Self.mapError(status: status, data: data)
        }

        throw MisarReachError.networkError(message: "max retries exceeded: \(lastError?.localizedDescription ?? "unknown")")
    }

    /// Maps a non-2xx response into a typed ``MisarReachError``.
    /// Percent-encodes a value for use as a single path segment.
    ///
    /// `.urlPathAllowed` is for an entire path and permits `/`, `@`, `+` and
    /// `&`, so a value containing one would change the shape of the URL rather
    /// than being carried inside a segment. Only unreserved characters are kept.
    internal static func encodeSegment(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    internal static func mapError(status: Int, data: Data) -> MisarReachError {
        let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let message = (obj["error"] as? String)
            ?? (obj["message"] as? String)
            ?? (String(data: data, encoding: .utf8).flatMap { $0.isEmpty ? nil : $0 })
            ?? "error"

        // A counted cap answers 402 with upgrade:true; older deployments used
        // 429. Either way it is a plan refusal, not a rate limit. This check has
        // to sit above the 429 branch: nested inside it, the `status == 402`
        // clause was unreachable and every real 402 refusal fell through to a
        // generic apiError.
        let upgrade = (obj["upgrade"] as? Bool) ?? false
        if upgrade, status == 402 || status == 429 {
            return .upgradeRequired(
                status: status,
                message: message,
                feature: obj["feature"] as? String,
                limit: (obj["limit"] as? NSNumber)?.intValue,
                current: (obj["current"] as? NSNumber)?.intValue,
                upgradeURL: Self.absoluteUpgradeURL(obj["upgrade_url"] as? String)
            )
        }

        if status == 429 {
            let balance = (obj["balance"] as? NSNumber)?.doubleValue ?? (obj["balance"] as? Double)
            let freeRemaining = (obj["freeRemaining"] as? NSNumber)?.intValue ?? (obj["freeRemaining"] as? Int)
            return .rateLimit(message: message, balance: balance, freeRemaining: freeRemaining, upgrade: upgrade)
        }

        let code = obj["code"] as? String
        return .apiError(status: status, message: message, code: code)
    }

    // MARK: Server-Sent Events

    /// Opens a Server-Sent Events stream and invokes `onEvent` for each event
    /// until the stream terminates. If the endpoint returns a plain JSON
    /// snapshot (job already finished), a single synthetic `snapshot` event is
    /// delivered instead.
    /// Opens the SSE stream and invokes `onEvent` per frame.
    ///
    /// The delegate hands over raw chunks rather than lines, because
    /// `URLSession.bytes(for:)` does not exist in swift-corelibs-foundation.
    /// Frames are therefore found by buffering and splitting on the blank line.
    ///
    /// Deliberately not retried: replaying a stream that failed mid-flight would
    /// duplicate whatever the caller already consumed.
    internal func stream(
        path: String,
        onEvent: @escaping (MisarReachStreamEvent) -> Void
    ) async throws {
        guard let url = URL(string: baseURL + path) else {
            throw MisarReachError.networkError(message: "Invalid URL: \(baseURL + path)")
        }

        var urlRequest = URLRequest(url: url, timeoutInterval: 300)
        urlRequest.httpMethod = "GET"
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")

        let state = ReachSSEState()

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            // Parsing state is confined to this serial queue, so the delegate
            // callbacks never race with each other.
            let queue = OperationQueue()
            queue.maxConcurrentOperationCount = 1

            let delegate = ReachSSEChunkDelegate(
                onResponse: { http in
                    state.status = http.statusCode
                    state.isStream = (http.value(forHTTPHeaderField: "Content-Type") ?? "")
                        .lowercased()
                        .contains("text/event-stream")
                },
                onChunk: { chunk in
                    // A refusal body, or a finished job's snapshot, is JSON
                    // rather than SSE: collect it and handle it at completion.
                    guard (200..<300).contains(state.status), state.isStream else {
                        state.wholeBody.append(chunk)
                        return
                    }
                    state.buffer.append(chunk)
                    while let frame = state.nextFrame() {
                        if let event = state.parse(frame) { onEvent(event) }
                    }
                },
                onComplete: { error in
                    guard !state.finished else { return }
                    state.finished = true

                    if let error {
                        continuation.resume(
                            throwing: MisarReachError.networkError(message: error.localizedDescription)
                        )
                        return
                    }
                    if state.status >= 400 {
                        continuation.resume(
                            throwing: MisarReachClient.mapError(status: state.status, data: state.wholeBody)
                        )
                        return
                    }
                    // A job that has already finished is answered with a JSON
                    // snapshot rather than a stream. Report the terminal event
                    // the SSE path would have sent, so a caller's switch works
                    // the same whether the job finished before or during the call.
                    if !state.isStream {
                        let obj = (try? JSONSerialization.jsonObject(with: state.wholeBody))
                            as? [String: Any] ?? [:]
                        onEvent(MisarReachStreamEvent(
                            event: obj["status"] as? String == "failed" ? "error" : "complete",
                            data: obj,
                            raw: String(data: state.wholeBody, encoding: .utf8) ?? ""
                        ))
                        continuation.resume()
                        return
                    }
                    // A trailing frame the server never closed with a blank line.
                    if let event = state.parse(state.drain()) { onEvent(event) }
                    continuation.resume()
                }
            )

            // The client's own configuration, not a fresh .default: it carries
            // the caller's timeouts, proxy settings and protocolClasses, so an
            // injected session's behaviour applies to streams too.
            let streamSession = URLSession(
                configuration: session.configuration,
                delegate: delegate,
                delegateQueue: queue
            )
            let task = streamSession.dataTask(with: urlRequest)
            task.resume()
        }
    }

    // MARK: - Resource accessors

    public var leads:         LeadsResource { LeadsResource(client: self) }
    public var ads:           AdsResource { AdsResource(client: self) }
    public var autopilot:     AutopilotResource { AutopilotResource(client: self) }
    public var campaigns:     CampaignsResource { CampaignsResource(client: self) }
    public var channels:      ChannelsResource { ChannelsResource(client: self) }
    public var contacts:      ContactsResource { ContactsResource(client: self) }
    public var conversations: ConversationsResource { ConversationsResource(client: self) }
    public var deals:         DealsResource { DealsResource(client: self) }
    public var pipeline:      PipelineResource { PipelineResource(client: self) }
    public var salesAgent:    SalesAgentResource { SalesAgentResource(client: self) }
    public var settings:      SettingsResource { SettingsResource(client: self) }
    public var plan:      PlanResource { PlanResource(client: self) }
    public var workspaces:    WorkspacesResource { WorkspacesResource(client: self) }
    public var campaignTemplates: CampaignTemplatesResource { CampaignTemplatesResource(client: self) }
    public var deliverability:    DeliverabilityResource { DeliverabilityResource(client: self) }
    public var notifications:     NotificationsResource { NotificationsResource(client: self) }
    public var webhooks:          WebhooksResource { WebhooksResource(client: self) }
}

// MARK: - LeadsResource (lead-finder)

public class LeadsResource {
    private let client: MisarReachClient
    init(client: MisarReachClient) { self.client = client }

    /// GET /lead-finder/account
    public func account() async throws -> [String: Any] {
        try await client.request(method: "GET", path: "/lead-finder/account")
    }

    /// GET /lead-finder/config
    public func config() async throws -> [String: Any] {
        try await client.request(method: "GET", path: "/lead-finder/config")
    }

    /// GET /lead-finder/leads
    public func list(params: String? = nil) async throws -> [String: Any] {
        let path = params.map { "/lead-finder/leads?\($0)" } ?? "/lead-finder/leads"
        return try await client.request(method: "GET", path: path)
    }

    /// GET /lead-finder/export
    public func export(params: String? = nil) async throws -> [String: Any] {
        let path = params.map { "/lead-finder/export?\($0)" } ?? "/lead-finder/export"
        return try await client.request(method: "GET", path: path)
    }

    /// POST /lead-finder/search — start an async lead search.
    public func search(_ data: [String: Any]) async throws -> [String: Any] {
        try await client.request(method: "POST", path: "/lead-finder/search", body: data)
    }

    /// POST /lead-finder/discover
    public func discoverCompanies(_ data: [String: Any]) async throws -> [String: Any] {
        try await client.request(method: "POST", path: "/lead-finder/discover", body: data)
    }

    /// POST /lead-finder/enrich
    public func enrich(_ data: [String: Any]) async throws -> [String: Any] {
        try await client.request(method: "POST", path: "/lead-finder/enrich", body: data)
    }

    /// POST /lead-finder/verify
    public func verifyEmails(_ data: [String: Any]) async throws -> [String: Any] {
        try await client.request(method: "POST", path: "/lead-finder/verify", body: data)
    }

    /// POST /lead-finder/score
    public func score(_ data: [String: Any]) async throws -> [String: Any] {
        try await client.request(method: "POST", path: "/lead-finder/score", body: data)
    }

    /// GET /lead-finder/jobs/{jobId}
    public func jobStatus(jobId: String) async throws -> [String: Any] {
        try await client.request(method: "GET", path: "/lead-finder/jobs/\(jobId)")
    }

    /// POST /lead-finder/jobs/{jobId}/feedback
    public func submitFeedback(jobId: String, data: [String: Any]) async throws -> [String: Any] {
        try await client.request(method: "POST", path: "/lead-finder/jobs/\(jobId)/feedback", body: data)
    }

    /// GET /lead-finder/jobs/{jobId}/stream — Server-Sent Events live progress.
    public func streamJob(
        jobId: String,
        onEvent: @escaping (MisarReachStreamEvent) -> Void
    ) async throws {
        try await client.stream(path: "/lead-finder/jobs/\(jobId)/stream", onEvent: onEvent)
    }

    /// GET /lead-finder/lists
    public func listLeadLists() async throws -> [String: Any] {
        try await client.request(method: "GET", path: "/lead-finder/lists")
    }

    /// POST /lead-finder/lists
    public func createLeadList(_ data: [String: Any]) async throws -> [String: Any] {
        try await client.request(method: "POST", path: "/lead-finder/lists", body: data)
    }

    /// POST /lead-finder/lists/{listId}/sync
    public func syncLeadList(listId: String, data: [String: Any] = [:]) async throws -> [String: Any] {
        try await client.request(method: "POST", path: "/lead-finder/lists/\(listId)/sync", body: data)
    }

    /// GET /lead-finder/saved-searches
    public func savedSearches() async throws -> [String: Any] {
        try await client.request(method: "GET", path: "/lead-finder/saved-searches")
    }

    /// POST /lead-finder/saved-searches
    public func createSavedSearch(_ data: [String: Any]) async throws -> [String: Any] {
        try await client.request(method: "POST", path: "/lead-finder/saved-searches", body: data)
    }

    /// DELETE /lead-finder/saved-searches/{id}
    public func deleteSavedSearch(id: String) async throws -> [String: Any] {
        try await client.request(method: "DELETE", path: "/lead-finder/saved-searches/\(id)")
    }

    /// GET /lead-finder/scoring-rules
    public func scoringRules() async throws -> [String: Any] {
        try await client.request(method: "GET", path: "/lead-finder/scoring-rules")
    }

    /// POST /lead-finder/scoring-rules
    public func createScoringRule(_ data: [String: Any]) async throws -> [String: Any] {
        try await client.request(method: "POST", path: "/lead-finder/scoring-rules", body: data)
    }

    /// PATCH /lead-finder/scoring-rules/{id}
    public func updateScoringRule(id: String, data: [String: Any]) async throws -> [String: Any] {
        try await client.request(method: "PATCH", path: "/lead-finder/scoring-rules/\(id)", body: data)
    }

    /// DELETE /lead-finder/scoring-rules/{id}
    public func deleteScoringRule(id: String) async throws -> [String: Any] {
        try await client.request(method: "DELETE", path: "/lead-finder/scoring-rules/\(id)")
    }

    /// GET /lead-finder/recommendations
    public func recommendations(params: String? = nil) async throws -> [String: Any] {
        let path = params.map { "/lead-finder/recommendations?\($0)" } ?? "/lead-finder/recommendations"
        return try await client.request(method: "GET", path: path)
    }

    /// GET /lead-finder/search-history
    public func searchHistory(params: String? = nil) async throws -> [String: Any] {
        let path = params.map { "/lead-finder/search-history?\($0)" } ?? "/lead-finder/search-history"
        return try await client.request(method: "GET", path: path)
    }

    /// POST /lead-finder/preview-message — public, no auth required.
    public func previewMessage(_ data: [String: Any]) async throws -> [String: Any] {
        try await client.request(method: "POST", path: "/lead-finder/preview-message", body: data)
    }

    /// POST /lead-finder/send-to-campaign
    public func sendToCampaign(_ data: [String: Any]) async throws -> [String: Any] {
        try await client.request(method: "POST", path: "/lead-finder/send-to-campaign", body: data)
    }

    /// POST /lead-finder/add-to-segment
    public func addToSegment(_ data: [String: Any]) async throws -> [String: Any] {
        try await client.request(method: "POST", path: "/lead-finder/add-to-segment", body: data)
    }

    /// GET /lead-finder/companies/{domain}
    public func company(domain: String) async throws -> [String: Any] {
        try await client.request(method: "GET", path: "/lead-finder/companies/\(domain)")
    }

    /// GET /lead-finder/companies/{domain}/people
    public func companyPeople(domain: String, params: String? = nil) async throws -> [String: Any] {
        let path = params.map { "/lead-finder/companies/\(domain)/people?\($0)" } ?? "/lead-finder/companies/\(domain)/people"
        return try await client.request(method: "GET", path: path)
    }
}

// MARK: - AdsResource

public class AdsResource {
    private let client: MisarReachClient
    init(client: MisarReachClient) { self.client = client }

    /// POST /ads/linkedin/company-audience
    public func linkedinCompanyAudience(_ data: [String: Any]) async throws -> [String: Any] {
        try await client.request(method: "POST", path: "/ads/linkedin/company-audience", body: data)
    }
}

// MARK: - AutopilotResource

public class AutopilotResource {
    private let client: MisarReachClient
    init(client: MisarReachClient) { self.client = client }

    /// GET /autopilot/runs
    public func runs(params: String? = nil) async throws -> [String: Any] {
        let path = params.map { "/autopilot/runs?\($0)" } ?? "/autopilot/runs"
        return try await client.request(method: "GET", path: path)
    }

    /// POST /autopilot/start
    public func start(_ data: [String: Any]) async throws -> [String: Any] {
        try await client.request(method: "POST", path: "/autopilot/start", body: data)
    }

    /// GET /autopilot/{id}
    public func get(id: String) async throws -> [String: Any] {
        try await client.request(method: "GET", path: "/autopilot/\(id)")
    }

    /// GET /autopilot/{id}/status
    public func status(id: String) async throws -> [String: Any] {
        try await client.request(method: "GET", path: "/autopilot/\(id)/status")
    }

    /// POST /autopilot/{id}/status
    public func setStatus(id: String, data: [String: Any]) async throws -> [String: Any] {
        try await client.request(method: "POST", path: "/autopilot/\(id)/status", body: data)
    }
}

// MARK: - CampaignsResource

public class CampaignsResource {
    private let client: MisarReachClient
    init(client: MisarReachClient) { self.client = client }

    /// GET /campaigns
    public func list(params: String? = nil) async throws -> [String: Any] {
        let path = params.map { "/campaigns?\($0)" } ?? "/campaigns"
        return try await client.request(method: "GET", path: path)
    }

    /// POST /campaigns
    public func create(_ data: [String: Any]) async throws -> [String: Any] {
        try await client.request(method: "POST", path: "/campaigns", body: data)
    }

    /// GET /campaigns/{id}
    public func get(id: String) async throws -> [String: Any] {
        try await client.request(method: "GET", path: "/campaigns/\(id)")
    }

    /// PATCH /campaigns/{id}
    public func update(id: String, data: [String: Any]) async throws -> [String: Any] {
        try await client.request(method: "PATCH", path: "/campaigns/\(id)", body: data)
    }

    /// DELETE /campaigns/{id}
    public func delete(id: String) async throws -> [String: Any] {
        try await client.request(method: "DELETE", path: "/campaigns/\(id)")
    }

    /// POST /campaigns/{id}/enqueue
    public func enqueue(id: String, data: [String: Any] = [:]) async throws -> [String: Any] {
        try await client.request(method: "POST", path: "/campaigns/\(id)/enqueue", body: data)
    }
}

// MARK: - ChannelsResource

public class ChannelsResource {
    private let client: MisarReachClient
    init(client: MisarReachClient) { self.client = client }

    /// GET /channels/status
    public func status() async throws -> [String: Any] {
        try await client.request(method: "GET", path: "/channels/status")
    }

    /// PATCH /channels/status
    public func updateStatus(_ data: [String: Any]) async throws -> [String: Any] {
        try await client.request(method: "PATCH", path: "/channels/status", body: data)
    }

    /// GET /channels/opt-in-links
    public func optInLinks(params: String? = nil) async throws -> [String: Any] {
        let path = params.map { "/channels/opt-in-links?\($0)" } ?? "/channels/opt-in-links"
        return try await client.request(method: "GET", path: path)
    }

    /// POST /channels/sms/connect
    public func connectSms(_ data: [String: Any]) async throws -> [String: Any] {
        try await client.request(method: "POST", path: "/channels/sms/connect", body: data)
    }

    /// POST /channels/whatsapp/connect
    public func connectWhatsapp(_ data: [String: Any]) async throws -> [String: Any] {
        try await client.request(method: "POST", path: "/channels/whatsapp/connect", body: data)
    }

    /// POST /channels/telegram/connect
    public func connectTelegram(_ data: [String: Any]) async throws -> [String: Any] {
        try await client.request(method: "POST", path: "/channels/telegram/connect", body: data)
    }

    /// POST /channels/twitter/connect
    public func connectTwitter(_ data: [String: Any]) async throws -> [String: Any] {
        try await client.request(method: "POST", path: "/channels/twitter/connect", body: data)
    }

    /// POST /channels/instagram/connect
    public func connectInstagram(_ data: [String: Any]) async throws -> [String: Any] {
        try await client.request(method: "POST", path: "/channels/instagram/connect", body: data)
    }

    /// POST /channels/facebook/connect
    public func connectFacebook(_ data: [String: Any]) async throws -> [String: Any] {
        try await client.request(method: "POST", path: "/channels/facebook/connect", body: data)
    }

    /// POST /channels/discord/connect
    public func connectDiscord(_ data: [String: Any]) async throws -> [String: Any] {
        try await client.request(method: "POST", path: "/channels/discord/connect", body: data)
    }

    /// POST /channels/push/subscribe
    public func subscribePush(_ data: [String: Any]) async throws -> [String: Any] {
        try await client.request(method: "POST", path: "/channels/push/subscribe", body: data)
    }

    /// DELETE /channels/push/subscribe
    public func unsubscribePush() async throws -> [String: Any] {
        try await client.request(method: "DELETE", path: "/channels/push/subscribe")
    }
}

// MARK: - ContactsResource

public class ContactsResource {
    private let client: MisarReachClient
    init(client: MisarReachClient) { self.client = client }

    /// GET /contacts
    public func list(params: String? = nil) async throws -> [String: Any] {
        let path = params.map { "/contacts?\($0)" } ?? "/contacts"
        return try await client.request(method: "GET", path: path)
    }

    /// POST /contacts
    public func create(_ data: [String: Any]) async throws -> [String: Any] {
        try await client.request(method: "POST", path: "/contacts", body: data)
    }

    /// GET /contacts/{id}
    public func get(id: String) async throws -> [String: Any] {
        try await client.request(method: "GET", path: "/contacts/\(id)")
    }

    /// PATCH /contacts/{id}
    public func update(id: String, data: [String: Any]) async throws -> [String: Any] {
        try await client.request(method: "PATCH", path: "/contacts/\(id)", body: data)
    }

    /// DELETE /contacts/{id}
    public func delete(id: String) async throws -> [String: Any] {
        try await client.request(method: "DELETE", path: "/contacts/\(id)")
    }

    /// POST /contacts/bulk
    public func bulk(_ data: [String: Any]) async throws -> [String: Any] {
        try await client.request(method: "POST", path: "/contacts/bulk", body: data)
    }

    /// POST /contacts/import
    public func importContacts(_ data: [String: Any]) async throws -> [String: Any] {
        try await client.request(method: "POST", path: "/contacts/import", body: data)
    }

    /// GET /contacts/segments
    public func segments() async throws -> [String: Any] {
        try await client.request(method: "GET", path: "/contacts/segments")
    }

    /// GET /contacts/stats
    public func stats() async throws -> [String: Any] {
        try await client.request(method: "GET", path: "/contacts/stats")
    }
}

// MARK: - ConversationsResource

public class ConversationsResource {
    private let client: MisarReachClient
    init(client: MisarReachClient) { self.client = client }

    /// GET /conversations
    public func list(params: String? = nil) async throws -> [String: Any] {
        let path = params.map { "/conversations?\($0)" } ?? "/conversations"
        return try await client.request(method: "GET", path: path)
    }

    /// GET /conversations/{email}
    public func get(email: String) async throws -> [String: Any] {
        let encoded = MisarReachClient.encodeSegment(email)
        return try await client.request(method: "GET", path: "/conversations/\(encoded)")
    }

    /// POST /conversations/{email}/reply
    public func reply(email: String, data: [String: Any]) async throws -> [String: Any] {
        let encoded = MisarReachClient.encodeSegment(email)
        return try await client.request(method: "POST", path: "/conversations/\(encoded)/reply", body: data)
    }
}

// MARK: - CampaignTemplatesResource

public class CampaignTemplatesResource {
    private let client: MisarReachClient
    init(client: MisarReachClient) { self.client = client }

    /// GET /campaign-templates
    public func list(params: String? = nil) async throws -> [String: Any] {
        let path = params.map { "/campaign-templates?\($0)" } ?? "/campaign-templates"
        return try await client.request(method: "GET", path: path)
    }

    /// POST /campaign-templates
    public func create(data: [String: Any]) async throws -> [String: Any] {
        try await client.request(method: "POST", path: "/campaign-templates", body: data)
    }
}

// MARK: - DeliverabilityResource

public class DeliverabilityResource {
    private let client: MisarReachClient
    init(client: MisarReachClient) { self.client = client }

    /// GET /deliverability
    ///
    /// `bounceRate` and `complaintRate` are null when there is not enough volume
    /// to judge — which is not the same as zero.
    public func get(params: String? = nil) async throws -> [String: Any] {
        let path = params.map { "/deliverability?\($0)" } ?? "/deliverability"
        return try await client.request(method: "GET", path: path)
    }
}

// MARK: - NotificationsResource

public class NotificationsResource {
    private let client: MisarReachClient
    init(client: MisarReachClient) { self.client = client }

    /// GET /notifications
    public func list(params: String? = nil) async throws -> [String: Any] {
        let path = params.map { "/notifications?\($0)" } ?? "/notifications"
        return try await client.request(method: "GET", path: path)
    }

    /// PATCH /notifications — pass `["ids": [...]]` or `["all": true]`.
    public func markRead(data: [String: Any]) async throws -> [String: Any] {
        try await client.request(method: "PATCH", path: "/notifications", body: data)
    }
}

// MARK: - WebhooksResource

public class WebhooksResource {
    private let client: MisarReachClient
    init(client: MisarReachClient) { self.client = client }

    /// GET /webhooks/endpoints
    public func list() async throws -> [String: Any] {
        try await client.request(method: "GET", path: "/webhooks/endpoints")
    }

    /// POST /webhooks/endpoints
    ///
    /// The response carries the signing secret exactly once — store it then; it
    /// is not retrievable afterwards.
    public func create(data: [String: Any]) async throws -> [String: Any] {
        try await client.request(method: "POST", path: "/webhooks/endpoints", body: data)
    }
}

// MARK: - DealsResource

public class DealsResource {
    private let client: MisarReachClient
    init(client: MisarReachClient) { self.client = client }

    /// GET /deals
    public func list(params: String? = nil) async throws -> [String: Any] {
        let path = params.map { "/deals?\($0)" } ?? "/deals"
        return try await client.request(method: "GET", path: path)
    }

    /// POST /deals
    public func create(_ data: [String: Any]) async throws -> [String: Any] {
        try await client.request(method: "POST", path: "/deals", body: data)
    }

    /// PATCH /deals/{id}
    public func update(id: String, data: [String: Any]) async throws -> [String: Any] {
        try await client.request(method: "PATCH", path: "/deals/\(id)", body: data)
    }

    /// DELETE /deals/{id}
    public func delete(id: String) async throws -> [String: Any] {
        try await client.request(method: "DELETE", path: "/deals/\(id)")
    }

    /// GET /deals/{id}/activity
    public func activity(id: String) async throws -> [String: Any] {
        try await client.request(method: "GET", path: "/deals/\(id)/activity")
    }

    /// GET /deals/{id}/suggestions
    public func suggestions(id: String) async throws -> [String: Any] {
        try await client.request(method: "GET", path: "/deals/\(id)/suggestions")
    }

    /// POST /deals/bulk — one operation over many deals,
    /// `["ids": [...], "op": "tag"|"untag"|"stage"|"delete", ...]`. Tag writes are
    /// applied atomically server-side, so concurrent callers cannot lose a tag.
    public func bulk(data: [String: Any]) async throws -> [String: Any] {
        try await client.request(method: "POST", path: "/deals/bulk", body: data)
    }
}

// MARK: - PipelineResource

public class PipelineResource {
    private let client: MisarReachClient
    init(client: MisarReachClient) { self.client = client }

    /// GET /pipeline
    public func get() async throws -> [String: Any] {
        try await client.request(method: "GET", path: "/pipeline")
    }

    /// POST /pipeline
    public func create(_ data: [String: Any]) async throws -> [String: Any] {
        try await client.request(method: "POST", path: "/pipeline", body: data)
    }
}

// MARK: - SalesAgentResource

public class SalesAgentResource {
    private let client: MisarReachClient
    init(client: MisarReachClient) { self.client = client }

    /// GET /sales-agent/actions
    public func actions(params: String? = nil) async throws -> [String: Any] {
        let path = params.map { "/sales-agent/actions?\($0)" } ?? "/sales-agent/actions"
        return try await client.request(method: "GET", path: path)
    }

    /// GET /sales-agent/config
    public func config() async throws -> [String: Any] {
        try await client.request(method: "GET", path: "/sales-agent/config")
    }

    /// PATCH /sales-agent/config
    public func updateConfig(_ data: [String: Any]) async throws -> [String: Any] {
        try await client.request(method: "PATCH", path: "/sales-agent/config", body: data)
    }

    /// GET /sales-agent/conversations
    public func conversations(params: String? = nil) async throws -> [String: Any] {
        let path = params.map { "/sales-agent/conversations?\($0)" } ?? "/sales-agent/conversations"
        return try await client.request(method: "GET", path: path)
    }

    /// POST /sales-agent/process
    public func process(_ data: [String: Any]) async throws -> [String: Any] {
        try await client.request(method: "POST", path: "/sales-agent/process", body: data)
    }
}

// MARK: - SettingsResource

public class SettingsResource {
    private let client: MisarReachClient
    init(client: MisarReachClient) { self.client = client }

    /// GET /settings/sender-address
    public func senderAddress() async throws -> [String: Any] {
        try await client.request(method: "GET", path: "/settings/sender-address")
    }

    /// PUT /settings/sender-address
    public func setSenderAddress(_ data: [String: Any]) async throws -> [String: Any] {
        try await client.request(method: "PUT", path: "/settings/sender-address", body: data)
    }
}

// MARK: - WorkspacesResource

public class WorkspacesResource {
    private let client: MisarReachClient
    init(client: MisarReachClient) { self.client = client }

    /// GET /workspaces
    public func list() async throws -> [String: Any] {
        try await client.request(method: "GET", path: "/workspaces")
    }

    /// POST /workspaces
    public func create(_ data: [String: Any]) async throws -> [String: Any] {
        try await client.request(method: "POST", path: "/workspaces", body: data)
    }

    /// GET /workspaces/{id}/members
    public func listMembers(id: String) async throws -> [String: Any] {
        try await client.request(method: "GET", path: "/workspaces/\(id)/members")
    }

    /// POST /workspaces/{id}/members
    public func addMember(id: String, data: [String: Any]) async throws -> [String: Any] {
        try await client.request(method: "POST", path: "/workspaces/\(id)/members", body: data)
    }

    /// DELETE /workspaces/{id}/members
    public func removeMember(id: String, params: String? = nil) async throws -> [String: Any] {
        let path = params.map { "/workspaces/\(id)/members?\($0)" } ?? "/workspaces/\(id)/members"
        return try await client.request(method: "DELETE", path: path)
    }
}

extension MisarReachClient {
    /// The server returns `upgrade_url` app-relative (`/settings?tab=billing`);
    /// resolve it against the app origin so callers can link to it.
    static func absoluteUpgradeURL(_ path: String?) -> String? {
        guard let path, !path.isEmpty else { return nil }
        if path.hasPrefix("http://") || path.hasPrefix("https://") { return path }
        return "https://misarreach.com" + (path.hasPrefix("/") ? path : "/" + path)
    }
}

// MARK: - SSE transport

/// Bridges `URLSession`'s delegate callbacks into chunk callbacks.
///
/// A data delegate is available on every platform, unlike
/// `URLSession.bytes(for:)`, so this keeps one implementation rather than two.
final class ReachSSEChunkDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let onResponse: (HTTPURLResponse) -> Void
    private let onChunk: (Data) -> Void
    private let onComplete: (Error?) -> Void

    init(
        onResponse: @escaping (HTTPURLResponse) -> Void,
        onChunk: @escaping (Data) -> Void,
        onComplete: @escaping (Error?) -> Void
    ) {
        self.onResponse = onResponse
        self.onChunk = onChunk
        self.onComplete = onComplete
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        if let http = response as? HTTPURLResponse { onResponse(http) }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        onChunk(data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        onComplete(error)
        // Invalidation must not run on the session's own delegate queue — it
        // waits for that queue to drain, and this callback runs on it.
        DispatchQueue.global().async { session.finishTasksAndInvalidate() }
    }
}

/// Mutable SSE parse state, owned by the delegate's serial queue.
final class ReachSSEState: @unchecked Sendable {
    var status = 0
    var isStream = false
    var finished = false
    var buffer = Data()
    /// A non-SSE body: either a refusal envelope or a finished job's snapshot.
    var wholeBody = Data()

    /// Pops the next complete frame, or nil when the buffer holds a partial one.
    func nextFrame() -> String? {
        let lf = buffer.range(of: Data("\n\n".utf8))
        let crlf = buffer.range(of: Data("\r\n\r\n".utf8))

        let chosen: Range<Data.Index>?
        switch (lf, crlf) {
        case (nil, nil):       chosen = nil
        case (let l?, nil):    chosen = l
        case (nil, let c?):    chosen = c
        case (let l?, let c?): chosen = l.lowerBound <= c.lowerBound ? l : c
        }
        guard let range = chosen else { return nil }

        let frame = String(data: buffer[buffer.startIndex..<range.lowerBound], encoding: .utf8) ?? ""
        buffer.removeSubrange(buffer.startIndex..<range.upperBound)
        return frame
    }

    /// Whatever is left once the socket closes.
    func drain() -> String {
        let rest = String(data: buffer, encoding: .utf8) ?? ""
        buffer.removeAll()
        return rest
    }

    /// Parses one frame, or nil for a keepalive comment or a frame with no data.
    func parse(_ frame: String) -> MisarReachStreamEvent? {
        var eventName = "message"
        var dataLines: [String] = []

        for rawLine in frame.replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            if line.isEmpty || line.hasPrefix(":") { continue }  // blank or keepalive
            if line.hasPrefix("event:") {
                eventName = line.dropFirst(6).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("data:") {
                var rest = String(line.dropFirst(5))
                // SSE strips exactly one space after the colon.
                if rest.hasPrefix(" ") { rest.removeFirst() }
                dataLines.append(rest)
            }
        }

        guard !dataLines.isEmpty else { return nil }

        let raw = dataLines.joined(separator: "\n")
        let obj = raw.data(using: .utf8)
            .flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any] ?? [:]
        return MisarReachStreamEvent(event: eventName, data: obj, raw: raw)
    }
}

// MARK: - PlanResource

/// The subscription behind the API key.
///
/// Read this before an expensive run rather than discovering the ceiling through
/// `MisarReachError.upgradeRequired` halfway through: a 402 says a call *was*
/// refused, whereas `usage` says what is left before anything is spent.
public final class PlanResource {
    private let client: MisarReachClient
    init(client: MisarReachClient) { self.client = client }

    /// `GET /plan` — plan, caps, per-feature usage and the upgrade offer.
    ///
    /// A null limit means unlimited, and `remaining` is null with it rather than
    /// 0 — 0 would read as exhausted.
    public func get() async throws -> [String: Any] {
        try await client.request(method: "GET", path: "/plan")
    }
}
