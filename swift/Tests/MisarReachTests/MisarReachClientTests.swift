import XCTest
@testable import MisarReach

// MARK: - URLSession stub

/// A `URLProtocol` subclass that intercepts requests and responds with a
/// pre-configured status code and body without making real network calls.
final class StubURLProtocol: URLProtocol {

    static var statusCode: Int = 200
    static var responseBody: Data = Data()
    static var lastRequest: URLRequest?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        StubURLProtocol.lastRequest = request
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: StubURLProtocol.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: StubURLProtocol.responseBody)
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

    func stub(status: Int, body: String) -> MisarReachClient {
        StubURLProtocol.statusCode = status
        StubURLProtocol.responseBody = Data(body.utf8)
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

    func test429_upgrade_setsFlag() async throws {
        let client = stub(status: 429, body: #"{"error":"upgrade","upgrade":true}"#)
        do {
            _ = try await client.leads.score(["jobId": "j1"])
            XCTFail("Expected rateLimit error")
        } catch MisarReachError.rateLimit(_, _, _, let upgrade) {
            XCTAssertTrue(upgrade)
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
}
