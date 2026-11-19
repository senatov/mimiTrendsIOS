import Foundation
import WebKit

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

@MainActor
final class WebPageNavigationLogger: NSObject, WKNavigationDelegate {
    let slot: String
    let target: String
    var navigationID = ""
    private var navigationIDs: [ObjectIdentifier: String] = [:]

    init(slot: String, target: String) {
        self.slot = slot
        self.target = target
    }

    func register(_ navigation: WKNavigation?, id: String) {
        navigationID = id
        if let navigation { navigationIDs[ObjectIdentifier(navigation)] = id }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        AppDiagnostics.shared.record(.info, "WebPage", "navigation-finish",
                                     "id=\(takeID(for: navigation)) slot=\(slot) target=\(BrowserPageRequest.diagnosticTarget(webView.url))")
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        logFailure(error, phase: "navigation", navigation: navigation)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
                 withError error: Error) {
        logFailure(error, phase: "provisional", navigation: navigation)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        AppDiagnostics.shared.record(.warning, "WebPage", "content-process-terminated",
                                     "id=\(navigationID) slot=\(slot) target=\(target)")
    }

    private func takeID(for navigation: WKNavigation?) -> String {
        guard let navigation else { return navigationID }
        return navigationIDs.removeValue(forKey: ObjectIdentifier(navigation)) ?? navigationID
    }

    private func logFailure(_ error: Error, phase: String, navigation: WKNavigation?) {
        let failure = error as NSError
        AppDiagnostics.shared.record(.warning, "WebPage", "navigation-failed",
                                     "id=\(takeID(for: navigation)) slot=\(slot) phase=\(phase) domain=\(failure.domain) code=\(failure.code) target=\(target)")
    }
}
