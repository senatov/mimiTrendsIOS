import Foundation

enum AppIdentity {
    static let name = "mimiTrendsiOS"

    private static let buildInfo: [String: String] = {
        guard let url = Bundle.main.url(forResource: "BuildInfo", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let values = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let info = values as? [String: String] else { return [:] }
        return info
    }()

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    static var windowTitle: String {
        let date = buildInfo["BuildDate"] ?? "—"
        let workstation = buildInfo["BuildWorkstation"] ?? "—"
        return "\(name) · \(version) · \(date) · \(workstation)"
    }
}
