import Foundation
import XCTest
@testable import MiMiTrends

final class BrowserPageRequestTests: XCTestCase {
    func testDesktopAgentKeepsRequestMethodBodyAndOtherHeaders() {
        var request = URLRequest(url: URL(string: "https://example.com/scan")!)
        request.httpMethod = "POST"
        request.httpBody = Data("{\"test\":true}".utf8)
        request.timeoutInterval = 12
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("MiMiTrends/1.0", forHTTPHeaderField: "User-Agent")

        let configured = BrowserPageRequest.configured(request)

        XCTAssertEqual(configured.httpMethod, "POST")
        XCTAssertEqual(configured.httpBody, request.httpBody)
        XCTAssertEqual(configured.timeoutInterval, 12)
        XCTAssertEqual(configured.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertTrue(BrowserPageRequest.desktopUserAgents.contains(
            configured.value(forHTTPHeaderField: "User-Agent") ?? ""))
    }

    func testAgentPoolContainsSeveralDesktopBrowsers() {
        let agents = BrowserPageRequest.desktopUserAgents
        XCTAssertGreaterThanOrEqual(agents.count, 5)
        XCTAssertTrue(agents.allSatisfy { $0.hasPrefix("Mozilla/5.0 (") && !$0.contains("Mobile") })
        XCTAssertTrue(agents.contains { $0.contains("Chrome/") })
        XCTAssertTrue(agents.contains { $0.contains("Firefox/") })
        XCTAssertTrue(agents.contains { $0.contains("Edg/") })
        XCTAssertTrue(agents.contains { $0.contains("Version/26.0 Safari/") })
    }

    func testDiagnosticTargetOmitsQueryCredentialsAndFragment() {
        let url = URL(string: "https://user:secret@example.com/quotes/AAPL?token=private#section")!
        XCTAssertEqual(BrowserPageRequest.diagnosticTarget(url), "https://example.com/quotes/AAPL")
        XCTAssertEqual(BrowserPageRequest.diagnosticTarget(nil), "unknown")
    }

    func testSendAppliesDesktopAgentToHTTPTransaction() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [BrowserPageEchoURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let request = URLRequest(url: URL(string: "https://example.com/page")!)

        let (data, response) = try await BrowserPageRequest.send(request, using: session)

        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertTrue(BrowserPageRequest.desktopUserAgents.contains(String(decoding: data, as: UTF8.self)))
    }
}

private final class BrowserPageEchoURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 200,
                                       httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data((request.value(forHTTPHeaderField: "User-Agent") ?? "").utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
