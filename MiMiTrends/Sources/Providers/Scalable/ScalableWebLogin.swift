import SwiftUI

/// Opens Scalable's public sign-in page. Browser authentication stays with Scalable;
/// the app has no registered callback or broker session to receive.
enum ScalableWebLogin {
    static let url = URL(string: "https://secure.scalable.capital/login")!

    @MainActor
    static func open(using openURL: OpenURLAction, source: String) {
        AppDiagnostics.shared.record(.info, "Scalable", "web-sign-in-requested", "source=\(source)")
        openURL(url) { accepted in
            AppDiagnostics.shared.record(
                accepted ? .info : .warning,
                "Scalable",
                accepted ? "web-sign-in-url-accepted" : "web-sign-in-url-rejected",
                "source=\(source)"
            )
        }
    }
}
