import Foundation

/// Opens Scalable's public sign-in page. Browser authentication stays with Scalable;
/// the app has no registered callback or broker session to receive.
enum ScalableWebLogin {
    static let url = URL(string: "https://secure.scalable.capital/login")!
}
