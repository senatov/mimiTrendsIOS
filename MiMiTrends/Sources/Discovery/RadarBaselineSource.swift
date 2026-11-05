import Foundation

/// Resolves the ranking's instrument pages using the publisher's identifiers.
actor RadarBaselineSource {
    private let source = MiminaviInfo1Source()
    private var resolved: [String: RadarCompanyCandidate] = [:]

    func loadCandidates() async throws -> [RadarCompanyCandidate] {
        let candidates = try await source.loadCandidates()
        var result: [RadarCompanyCandidate] = []
        for start in stride(from: 0, to: candidates.count, by: 4) {
            try Task.checkCancellation()
            let batch = Array(candidates[start..<min(start + 4, candidates.count)])
            let cached = resolved
            let loaded = await withTaskGroup(of: (String, RadarCompanyCandidate?).self) { group in
                for candidate in batch {
                    group.addTask {
                        if let value = cached[candidate.instrumentID] {
                            return (candidate.instrumentID, value)
                        }
                        return (candidate.instrumentID, try? await Self.resolve(candidate))
                    }
                }
                var values: [String: RadarCompanyCandidate] = [:]
                for await (id, value) in group { values[id] = value }
                return values
            }
            for candidate in batch {
                if let value = loaded[candidate.instrumentID] {
                    resolved[candidate.instrumentID] = value
                    result.append(value)
                }
            }
        }
        var seen = Set<String>()
        return result.filter { seen.insert($0.symbol).inserted }
    }

    private static func searchISIN(_ isin: String) async throws -> String? {
        var components = URLComponents(string: "https://query1.finance.yahoo.com/v1/finance/search")!
        components.queryItems = [URLQueryItem(name: "q", value: isin),
                                 URLQueryItem(name: "quotesCount", value: "10"),
                                 URLQueryItem(name: "newsCount", value: "0")]
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let quotes = root["quotes"] as? [[String: Any]] else { return nil }
        return quotes.first(where: {
            $0["quoteType"] as? String == "EQUITY" &&
            ($0["symbol"] as? String).map(MarketCandidateFilter.supportsYahooBars) == true
        })?["symbol"] as? String
    }

    private static func resolve(_ candidate: DiscoveryCandidate) async throws -> RadarCompanyCandidate? {
        guard let url = URL(string: candidate.instrumentID,
                            relativeTo: URL(string: "https://www.wallstreet-online.de")!) else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              http.url?.host == "www.wallstreet-online.de", data.count <= 2_000_000,
              let html = String(data: data, encoding: .utf8) else { return nil }
        let pattern = #""propertyID"\s*:\s*"(ISIN|ticker)"\s*,\s*"value"\s*:\s*"([A-Z0-9.\-]+)""#
        let regex = try NSRegularExpression(pattern: pattern)
        var identifiers: [String: String] = [:]
        for match in regex.matches(in: html, range: NSRange(html.startIndex..., in: html)) {
            guard let key = Range(match.range(at: 1), in: html),
                  let value = Range(match.range(at: 2), in: html) else { continue }
            identifiers[String(html[key])] = String(html[value])
        }
        guard let isin = identifiers["ISIN"], let ticker = identifiers["ticker"] else { return nil }
        // The publisher's German ticker identifies the local listing. Never treat it as a US ticker.
        let symbol: String
        if isin.hasPrefix("DE") {
            symbol = ticker.hasSuffix(".DE") ? ticker : ticker + ".DE"
        } else {
            guard let matched = try await searchISIN(isin) else { return nil }
            symbol = matched
        }
        guard MarketCandidateFilter.supportsYahooBars(symbol: symbol) else { return nil }
        return RadarCompanyCandidate(symbol: symbol, name: candidate.displayName ?? ticker)
    }
}
