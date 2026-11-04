import Foundation

enum ReutersSearch {
    static func url(symbol: String) -> URL? {
        let ticker = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard MarketCandidateFilter.supportsYahooBars(symbol: ticker),
              var components = URLComponents(string: "https://www.reuters.com/site-search/") else { return nil }
        components.queryItems = [URLQueryItem(name: "query", value: ticker)]
        return components.url
    }
}
