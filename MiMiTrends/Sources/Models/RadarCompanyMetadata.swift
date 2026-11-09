import Foundation

struct RadarCompanyMetadata: Codable, Sendable {
    let symbol: String
    let name: String
    let countryCode: String?
    let logoData: Data?
    let updatedAtMillis: Int64

    var flag: String? {
        Self.flag(for: countryCode)
    }

    static func flag(for countryCode: String?) -> String? {
        guard let countryCode, countryCode.count == 2,
              countryCode.uppercased().unicodeScalars.allSatisfy({ (65...90).contains($0.value) }) else { return nil }
        let scalars = countryCode.uppercased().unicodeScalars.compactMap { scalar -> UnicodeScalar? in
            guard let value = UnicodeScalar(0x1F1E6 + scalar.value - 65) else { return nil }
            return value
        }
        return scalars.count == 2 ? String(String.UnicodeScalarView(scalars)) : nil
    }

    static func countryFallback(for symbol: String) -> String? {
        // Lang & Schwarz quote identifiers refer to instruments traded on its German venue.
        // They are not exchange tickers, so suffix-based country detection cannot resolve them.
        if symbol.uppercased().hasPrefix("LS:") { return "DE" }
        let suffix = symbol.uppercased().split(separator: ".").last
        return switch suffix {
        case "DE", "F", "BE", "DU", "HM", "MU", "SG", "HA", "X": "DE"
        case "PA": "FR"
        case "BR": "BE"
        case "AS": "NL"
        case "MI": "IT"
        case "HE": "FI"
        case "L": "GB"
        case "SW": "CH"
        case "TO": "CA"
        case "HK": "HK"
        case "T": "JP"
        case "KS", "KQ": "KR"
        case "SS": "CN"
        default: nil
        }
    }
}
