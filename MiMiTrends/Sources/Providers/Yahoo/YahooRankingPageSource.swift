import Foundation

struct YahooRankingPageSource: Sendable {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func loadCandidates(from url: URL, limit: Int = 100) async throws -> [RadarCompanyCandidate] {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw RadarSourceError.invalidResponse }
        if response.statusCode == 429 { throw RadarSourceError.rateLimited }
        guard response.statusCode == 200 else { throw RadarSourceError.httpStatus(response.statusCode) }
        guard data.count <= 8_000_000, let html = String(data: data, encoding: .utf8) else {
            throw RadarSourceError.invalidResponse
        }
        let candidates = Self.candidates(in: html, limit: limit)
        guard !candidates.isEmpty else { throw RadarSourceError.invalidResponse }
        return candidates
    }

    static func candidates(in html: String, limit: Int = 100) -> [RadarCompanyCandidate] {
        guard limit > 0 else { return [] }
        let pattern = #"(?is)<a\b[^>]*href=[\"'](?:https?://(?:www\.)?finance\.yahoo\.com)?/(?:quote|symbol)/([^/\"'?#]+)[^\"']*[\"'][^>]*>(.*?)</a>"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(html.startIndex..., in: html)
        var seen = Set<String>()
        var result: [RadarCompanyCandidate] = []
        for match in regex.matches(in: html, range: range) {
            guard let symbolRange = Range(match.range(at: 1), in: html),
                  let nameRange = Range(match.range(at: 2), in: html) else { continue }
            let rawSymbol = String(html[symbolRange])
            let symbol = rawSymbol.removingPercentEncoding ?? rawSymbol
            guard isEquityCandidate(symbol),
                  seen.insert(symbol.uppercased()).inserted else { continue }
            let text = MarketPageHTML.plainText(String(html[nameRange]))
            let name = text.isEmpty ? symbol : text
            result.append(RadarCompanyCandidate(symbol: symbol, name: name))
            if result.count >= max(0, limit) { break }
        }
        return result
    }

    private static func isEquityCandidate(_ symbol: String) -> Bool {
        let normalized = symbol.uppercased()
        let nonEquitySuffixes = ["-USD", "-EUR", "-BTC", "=X", "=F"]
        return !normalized.hasPrefix("^") &&
            !nonEquitySuffixes.contains(where: normalized.hasSuffix) &&
            MarketCandidateFilter.supportsYahooBars(symbol: normalized)
    }
}
