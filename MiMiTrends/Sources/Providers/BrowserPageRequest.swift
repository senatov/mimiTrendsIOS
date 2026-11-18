import Foundation

/// Adds a common desktop browser identity to outgoing provider requests.
enum BrowserPageRequest {
    static let desktopUserAgents = [
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36",
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36",
        "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36",
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36 Edg/143.0.0.0",
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:145.0) Gecko/20100101 Firefox/145.0",
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15"
    ]

    static func randomUserAgent() -> String { desktopUserAgents.randomElement()! }

    static func configured(_ original: URLRequest) -> URLRequest {
        var request = original
        request.setValue(randomUserAgent(), forHTTPHeaderField: "User-Agent")
        return request
    }

    static func send(_ original: URLRequest, using session: URLSession = .shared) async throws
        -> (Data, URLResponse) {
        try await session.data(for: configured(original))
    }
}
