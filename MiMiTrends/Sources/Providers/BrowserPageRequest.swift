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

    static func diagnosticTarget(_ url: URL?) -> String {
        guard let url, let scheme = url.scheme, let host = url.host,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return "unknown"
        }
        return "\(scheme)://\(host)\(components.percentEncodedPath)"
    }

    static func send(_ original: URLRequest, using session: URLSession = .shared) async throws
        -> (Data, URLResponse) {
        let request = configured(original)
        let id = String(UUID().uuidString.prefix(8))
        let target = diagnosticTarget(request.url)
        let startedAt = Date()
        AppDiagnostics.shared.record(.info, "HTTP", "request-start",
                                     "id=\(id) method=\(request.httpMethod ?? "GET") target=\(target)")
        do {
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode
            let elapsedMillis = Int(Date().timeIntervalSince(startedAt) * 1_000)
            AppDiagnostics.shared.record((status ?? 0) >= 400 ? .warning : .info,
                                         "HTTP", "request-finish",
                                         "id=\(id) status=\(status.map(String.init) ?? "none") bytes=\(data.count) elapsedMs=\(elapsedMillis) target=\(diagnosticTarget(response.url))")
            return (data, response)
        } catch {
            let failure = error as NSError
            let elapsedMillis = Int(Date().timeIntervalSince(startedAt) * 1_000)
            let level: AppDiagnostics.Level = error is CancellationError ||
                (failure.domain == NSURLErrorDomain && failure.code == NSURLErrorCancelled)
                ? .info : .warning
            AppDiagnostics.shared.record(level, "HTTP", "request-failed",
                                         "id=\(id) domain=\(failure.domain) code=\(failure.code) elapsedMs=\(elapsedMillis) target=\(target)")
            throw error
        }
    }
}
