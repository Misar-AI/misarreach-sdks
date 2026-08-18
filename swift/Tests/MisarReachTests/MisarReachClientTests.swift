import XCTest
@testable import MisarReach

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - URLSession stub

/// A `URLProtocol` subclass that intercepts requests and responds with a
/// pre-configured status code and body without making real network calls.
final class StubURLProtocol: URLProtocol {

    static var statusCode: Int = 200
    static var responseBody: Data = Data()
    static var lastRequest: URLRequest?
    static var contentType: String = "application/json"
    /// Delivered in order, one `didLoad:` per element, so a frame boundary can
    /// land mid-chunk. Falls back to `responseBody` when empty.
    static var pieces: [String] = []

    static func reset() {
        statusCode = 200
        responseBody = Data()
        lastRequest = nil
        contentType = "application/json"
        pieces = []
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        StubURLProtocol.lastRequest = request
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: StubURLProtocol.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": StubURLProtocol.contentType]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if StubURLProtocol.pieces.isEmpty {
            client?.urlProtocol(self, didLoad: StubURLProtocol.responseBody)
        } else {
            for piece in StubURLProtocol.pieces {
                client?.urlProtocol(self, didLoad: Data(piece.utf8))
            }
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

// MARK: - Test helpers

extension MisarReachClientTests {

    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }

    func stub(status: Int, body: String, contentType: String = "application/json") -> MisarReachClient {
        StubURLProtocol.reset()
        StubURLProtocol.statusCode = status
        StubURLProtocol.responseBody = Data(body.utf8)
        StubURLProtocol.contentType = contentType
        return MisarReachClient(
            apiKey: "mrk_test_key",
            maxRetries: 1,
            session: Self.makeSession()
        )
    }

    /// Streams the given pieces as one `text/event-stream` body.
    func stubStream(pieces: [String]) -> MisarReachClient {
        StubURLProtocol.reset()
        StubURLProtocol.contentType = "text/event-stream"
        StubURLProtocol.pieces = pieces
        return MisarReachClient(
            apiKey: "mrk_test_key",
            maxRetries: 1,
            session: Self.makeSession()
        )
    }
}

// MARK: - Tests

final class MisarReachClientTests: XCTestCase {

    func testLeadsSearch_200_returnsParsedResponse() async throws {
        let client = stub(status: 200, body: #"{"jobId":"job_1","status":"running"}"#)
        let result = try await client.leads.search(["query": "saas founders"])
        XCTAssertEqual(result["jobId"] as? String, "job_1")
        XCTAssertEqual(StubURLProtocol.lastRequest?.url?.path, "/reach/api/lead-finder/search")
    }

    func testLeadsList_200_returnsParsedResponse() async throws {
        let client = stub(status: 200, body: #"{"data":[],"total":0}"#)
        let result = try await client.leads.list(params: "page=1&limit=20")
        XCTAssertNotNil(result["data"])
    }

    func testDealsCreate_201_returnsParsedResponse() async throws {
        let client = stub(status: 201, body: #"{"id":"deal_1","title":"Acme"}"#)
        let result = try await client.deals.create(["title": "Acme"])
        XCTAssertEqual(result["id"] as? String, "deal_1")
    }

    func testChannelsStatus_200_returnsParsedResponse() async throws {
        let client = stub(status: 200, body: #"{"sms":true,"whatsapp":false}"#)
        let result = try await client.channels.status()
        XCTAssertEqual(result["sms"] as? Bool, true)
    }

    func testPipelineGet_200_returnsParsedResponse() async throws {
        let client = stub(status: 200, body: #"{"stages":[]}"#)
        let result = try await client.pipeline.get()
        XCTAssertNotNil(result["stages"])
    }

    func testPreviewMessage_200_returnsParsedResponse() async throws {
        let client = stub(status: 200, body: #"{"message":"Hi there"}"#)
        let result = try await client.leads.previewMessage(["lead": ["name": "Jane"]])
        XCTAssertEqual(result["message"] as? String, "Hi there")
    }

    func testNon2xx_throwsApiError_withCorrectStatus() async throws {
        let client = stub(status: 401, body: #"{"error":"Unauthorized"}"#)
        do {
            _ = try await client.leads.search(["query": "x"])
            XCTFail("Expected MisarReachError to be thrown")
        } catch MisarReachError.apiError(let status, _, _) {
            XCTAssertEqual(status, 401)
        }
    }

    func test404_throwsApiError() async throws {
        let client = stub(status: 404, body: #"{"error":"not found"}"#)
        do {
            _ = try await client.deals.activity(id: "missing")
            XCTFail("Expected MisarReachError to be thrown")
        } catch MisarReachError.apiError(let status, _, _) {
            XCTAssertEqual(status, 404)
        }
    }

    func test429_throwsRateLimit_withFields() async throws {
        let client = stub(status: 429, body: #"{"error":"rate limited","balance":12.5,"freeRemaining":3}"#)
        do {
            _ = try await client.leads.enrich(["email": "a@b.com"])
            XCTFail("Expected rateLimit error")
        } catch MisarReachError.rateLimit(_, let balance, let freeRemaining, let upgrade) {
            XCTAssertEqual(balance, 12.5)
            XCTAssertEqual(freeRemaining, 3)
            XCTAssertFalse(upgrade)
        }
    }

    func testUpgradeRefusalOn429IsTypedAsARefusal() async throws {
        // A body carrying `upgrade: true` is a plan refusal whatever the status.
        // 402 is what the server sends now; 429 is still accepted so an older
        // deployment is not mistaken for a plain rate limit, which a caller
        // would retry pointlessly.
        let client = stub(
            status: 429,
            body: #"{"error":"monthly lead searches used up","upgrade":true,"feature":"lead_searches"}"#
        )

        do {
            _ = try await client.leads.score(["jobId": "j1"])
            XCTFail("expected a refusal")
        } catch let error as MisarReachError {
            guard case .upgradeRequired(let status, _, let feature, _, _, _) = error else {
                return XCTFail("expected upgradeRequired, got \(error)")
            }
            XCTAssertEqual(status, 429)
            XCTAssertEqual(feature, "lead_searches")
        }
    }

    func testEmptyBody_200_returnsEmptyDict() async throws {
        let client = stub(status: 200, body: "")
        let result = try await client.contacts.stats()
        XCTAssertTrue(result.isEmpty)
    }

    func testConversationsGet_encodesEmail() async throws {
        let client = stub(status: 200, body: #"{"messages":[]}"#)
        _ = try await client.conversations.get(email: "jane@acme.com")
        XCTAssertTrue(StubURLProtocol.lastRequest?.url?.absoluteString.contains("jane%40acme.com") ?? false)
    }

    // MARK: - Server-Sent Events

    func testJobStreamEmitsEachNamedFrame() async throws {
        // MisarReach names its events and sends `: keepalive` every 20s. The
        // boundary between the first two frames is split across two chunks.
        let client = stubStream(pieces: [
            "event: progress\ndata: {\"message\":\"searching\"}\n",
            "\n: keepalive\n\n",
            "event: found\ndata: {\"total\":12}\n\n",
            "event: complete\ndata: {\"total_found\":12}\n\n",
        ])

        var seen: [MisarReachStreamEvent] = []
        try await client.leads.streamJob(jobId: "job_1") { seen.append($0) }

        // The keepalive comment must not surface as an event.
        XCTAssertEqual(seen.map(\.event), ["progress", "found", "complete"])
        XCTAssertEqual(seen[1].data["total"] as? Int, 12)
    }

    func testJobStreamReportsAnAlreadyFinishedJob() async throws {
        // A finished job is answered with a JSON snapshot rather than a stream.
        // Parsed as SSE this emits nothing, so the caller could not tell a
        // finished job from a silent one.
        let client = stub(
            status: 200,
            body: #"{"status":"done","total_found":42,"error":null}"#,
            contentType: "application/json"
        )

        var seen: [MisarReachStreamEvent] = []
        try await client.leads.streamJob(jobId: "job_done") { seen.append($0) }

        XCTAssertEqual(seen.count, 1)
        XCTAssertEqual(seen.first?.event, "complete")
        XCTAssertEqual(seen.first?.data["total_found"] as? Int, 42)
    }

    func testJobStreamReportsAFailedJobAsError() async throws {
        let client = stub(
            status: 200,
            body: #"{"status":"failed","error":"no sources reachable"}"#,
            contentType: "application/json"
        )

        var seen: [MisarReachStreamEvent] = []
        try await client.leads.streamJob(jobId: "job_bad") { seen.append($0) }

        XCTAssertEqual(seen.first?.event, "error")
    }

    func testJobStreamRefusalIsTyped() async throws {
        let client = stub(
            status: 402,
            body: """
            {"error":"monthly lead searches used up","upgrade":true,
             "feature":"lead_searches","limit":50,"current":50,
             "upgrade_url":"/settings?tab=billing"}
            """
        )

        do {
            try await client.leads.streamJob(jobId: "job_1") { _ in
                XCTFail("no frame should be delivered on a refusal")
            }
            XCTFail("expected a refusal")
        } catch let error as MisarReachError {
            // A plan refusal on the stream must be the same typed error the
            // JSON helper raises.
            guard case .upgradeRequired(let status, _, let feature, _, _, let upgradeURL) = error else {
                return XCTFail("expected upgradeRequired, got \(error)")
            }
            XCTAssertEqual(status, 402)
            XCTAssertEqual(feature, "lead_searches")
            // The server sends it app-relative; the SDK resolves it.
            XCTAssertEqual(upgradeURL, "https://misarreach.com/settings?tab=billing")
        }
    }
}
