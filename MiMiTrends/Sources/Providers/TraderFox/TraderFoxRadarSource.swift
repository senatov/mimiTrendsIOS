import Foundation

struct TraderFoxRadarSource: Sendable {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func activeCandidates(limit: Int = 20) async throws -> [RadarCompanyCandidate] {
        let url = URL(string: "alle-nyse-aktien-bestandteile",
                      relativeTo: ProviderEndpointStore.url(for: .traderFox))!.absoluteURL
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Mozilla/5.0 MiMiTrends", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse,
              response.statusCode == 200, data.count <= 3_000_000,
              let html = String(data: data, encoding: .utf8) else {
            throw RadarSourceError.invalidResponse
        }
        return try Self.decodeCandidates(html, limit: limit, nowSeconds: Int64(Date().timeIntervalSince1970))
    }

    static func decode(_ html: String, limit: Int, nowSeconds: Int64) throws -> [String] {
        try decodeCandidates(html, limit: limit, nowSeconds: nowSeconds).map(\.symbol)
    }

    static func decodeCandidates(_ html: String, limit: Int, nowSeconds: Int64) throws -> [RadarCompanyCandidate] {
        let pattern = #"var\s+equities\s*=\s*(\{.*?\});"#
        guard let expression = try? NSRegularExpression(pattern: pattern, options: .dotMatchesLineSeparators),
              let match = expression.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let range = Range(match.range(at: 1), in: html),
              let data = String(html[range]).data(using: .utf8),
              let root = try JSONSerialization.jsonObject(with: data) as? [String: [String: Any]] else {
            throw RadarSourceError.invalidResponse
        }
        var seen = Set<String>()
        return root.values.compactMap { row -> (RadarCompanyCandidate, Double)? in
            guard row["active"] as? String == "Y",
                  row["currency"] as? String == "USD",
                  let raw = row["symbol"] as? String else { return nil }
            let symbol = raw.uppercased().replacingOccurrences(of: ".", with: "-")
            guard let price = (row["v"] as? NSNumber)?.doubleValue,
                  let change = (row["p"] as? NSNumber)?.doubleValue, change.isFinite,
                  let quoted = (row["t"] as? NSNumber)?.int64Value,
                  nowSeconds - quoted >= 0, nowSeconds - quoted <= 7 * 86_400 else { return nil }
            let name = (row["name"] as? String) ?? symbol
            guard MarketCandidateFilter.accepts(
                symbol: symbol, name: name, price: price, exchange: "NYSE", currency: "USD"
            ), seen.insert(symbol).inserted else { return nil }
            return (RadarCompanyCandidate(symbol: symbol, name: name), abs(change))
        }
        .sorted { $0.1 == $1.1 ? $0.0.symbol < $1.0.symbol : $0.1 > $1.1 }
        .prefix(max(0, limit))
        .map(\.0)
    }
}
