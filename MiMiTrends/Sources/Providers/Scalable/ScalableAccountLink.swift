import SwiftUI

/// Opens Scalable's account URL in the user's chosen system destination.
/// The OS may route it to Scalable's installed app. No broker session is returned.
enum ScalableAccountLink {
    static let url = URL(string: "https://secure.scalable.capital/login")!

    @MainActor
    static func open(using openURL: OpenURLAction, source: String) {
        AppDiagnostics.shared.record(.info, "Scalable", "account-open-requested", "source=\(source)")
        openURL(url)
    }
}
