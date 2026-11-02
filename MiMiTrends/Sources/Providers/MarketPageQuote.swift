import Foundation

struct MarketPageQuote: Sendable, Equatable {
    let identifier: String
    let name: String
    let path: String
    let bidEUR: Double
    let askEUR: Double
    let sourceCurrency: String
    let sourceBid: Double
    let sourceAsk: Double
    let euroUSDRate: Double?
    let fxObservedAtMillis: Int64?
    let observedAtMillis: Int64

    var midpointEUR: Double { (bidEUR + askEUR) / 2 }

    var isValid: Bool {
        let divisor = euroUSDRate ?? 1
        return !identifier.isEmpty && !name.isEmpty && path.hasPrefix("/de/aktie/") &&
            bidEUR.isFinite && askEUR.isFinite && bidEUR > 0 && askEUR >= bidEUR &&
            (sourceCurrency == "EUR" || sourceCurrency == "USD") &&
            sourceBid.isFinite && sourceAsk.isFinite && sourceBid > 0 && sourceAsk >= sourceBid &&
            (sourceCurrency == "EUR" && euroUSDRate == nil && fxObservedAtMillis == nil ||
             sourceCurrency == "USD" && euroUSDRate.map { $0 > 0.5 && $0 < 2 } == true &&
                fxObservedAtMillis.map { abs($0 - observedAtMillis) <= 5 * 60_000 } == true) &&
            abs(bidEUR - sourceBid / divisor) < 0.0001 &&
            abs(askEUR - sourceAsk / divisor) < 0.0001 &&
            observedAtMillis > 0
    }
}

enum MarketPageHTML {
    static func matches(_ pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return []
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard let swiftRange = Range(match.range(at: 1), in: text) else { return nil }
            return String(text[swiftRange])
        }
    }

    static func first(_ pattern: String, in text: String) -> String? {
        matches(pattern, in: text).first
    }

    static func plainText(_ html: String) -> String {
        let noTags = html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        return noTags.replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&#160;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func germanNumber(_ text: String) -> Double? {
        let normalized = plainText(text).replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: ",", with: ".")
            .replacingOccurrences(of: "[^0-9.+-]", with: "", options: .regularExpression)
        guard let value = Double(normalized), value.isFinite, value > 0 else { return nil }
        return value
    }

    static func quoteTime(_ timeText: String, now: Date) -> Int64? {
        let fields = timeText.split(separator: ":").compactMap { Int($0) }
        guard fields.count == 3, (0...23).contains(fields[0]),
              (0...59).contains(fields[1]), (0...59).contains(fields[2]) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        guard var candidate = calendar.date(bySettingHour: fields[0], minute: fields[1],
                                            second: fields[2], of: now) else { return nil }
        if candidate.timeIntervalSince(now) > 30 { candidate = calendar.date(byAdding: .day, value: -1, to: candidate)! }
        let age = now.timeIntervalSince(candidate)
        guard age >= -30, age <= 600 else { return nil }
        return Int64(candidate.timeIntervalSince1970 * 1_000)
    }
}
