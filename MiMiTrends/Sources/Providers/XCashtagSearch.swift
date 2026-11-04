import Foundation

enum XCashtagSearch {
    static func latestURL(symbol: String, now: Date = .now) -> URL? {
        let ticker = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard MarketCandidateFilter.supportsYahooBars(symbol: ticker),
              var components = URLComponents(string: "https://x.com/search") else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        let earliestDay = formatter.string(from: now.addingTimeInterval(-2 * 3_600))
        components.queryItems = [
            URLQueryItem(name: "q", value: "$\(ticker) since:\(earliestDay)"),
            URLQueryItem(name: "f", value: "live")
        ]
        return components.url
    }
}
