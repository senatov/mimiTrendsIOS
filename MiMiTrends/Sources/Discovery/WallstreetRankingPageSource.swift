import Foundation

enum WallstreetRankingKind: String, CaseIterable, Sendable {
    case wikifolio, performance
    var title: String { self == .wikifolio ? "Wikifolio activity" : "Price performance" }
    var endpoint: ProviderEndpoint { self == .wikifolio ? .wallstreetWikifolio : .wallstreetPerformance }
}

struct WallstreetRankingEntry: Equatable, Sendable {
    let path: String
    let name: String
    let rank: Int
    let trades: Int?
    let metrics: DiscoveryMarketMetrics?
}

struct WallstreetRankingPageSource: Sendable {
    let session: URLSession
    init(session: URLSession = .shared) { self.session = session }

    func load(_ kind: WallstreetRankingKind) async throws -> [WallstreetRankingEntry] {
        var request = URLRequest(url: ProviderEndpointStore.url(for: kind.endpoint))
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Mozilla/5.0 MiMiTrends", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              data.count <= 3_000_000, let html = String(data: data, encoding: .utf8) else {
            throw DiscoveryDataError.invalidCandidate
        }
        return try Self.decode(html, kind: kind)
    }

    static func decode(_ html: String, kind: WallstreetRankingKind) throws -> [WallstreetRankingEntry] {
        // Tooltips contain nested tables; remove their attributes before reading real table rows.
        let clean = html.replacingOccurrences(of: #"data-bs-title="[^"]*""#,
                                              with: "", options: .regularExpression)
        let tables = MarketPageHTML.matches(#"<table\b[^>]*>(.*?)</table>"#, in: clean)
        guard let table = tables.first(where: {
            $0.contains("Wertpapier") && $0.contains(kind == .wikifolio ? "Käufe/Verkäufe" : "Perf. %")
        }), let header = MarketPageHTML.first(#"<thead\b[^>]*>(.*?)</thead>"#, in: table) else {
            throw DiscoveryDataError.invalidCandidate
        }
        let columns = MarketPageHTML.matches(#"<th\b[^>]*>(.*?)</th>"#, in: header)
            .map { MarketPageHTML.plainText($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        var seen = Set<String>()
        let entries = MarketPageHTML.matches(#"<tr\b[^>]*>(.*?)</tr>"#, in: table).compactMap { row -> WallstreetRankingEntry? in
            let cells = MarketPageHTML.matches(#"<td\b[^>]*>(.*?)</td>"#, in: row)
            guard let first = cells.first,
                  let rank = Int(MarketPageHTML.plainText(first).replacingOccurrences(of: ".", with: "")),
                  (1...50).contains(rank),
                  let link = MarketPageHTML.first(#"href="(/aktien/[a-z0-9]+(?:-[a-z0-9]+)*)""#, in: row),
                  let name = MarketPageHTML.first(#"<a\b[^>]*href="/aktien/[^"\s]+"[^>]*>(.*?)</a>"#, in: row),
                  seen.insert(link).inserted else { return nil }
            func number(_ title: String) -> Double? {
                guard let index = columns.firstIndex(of: title), index < cells.count else { return nil }
                let text = MarketPageHTML.plainText(cells[index])
                    .replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
                    .replacingOccurrences(of: #"[^0-9.+-]"#, with: "", options: .regularExpression)
                guard let value = Double(text), value.isFinite else { return nil }
                return value
            }
            let metrics: DiscoveryMarketMetrics?
            if kind == .performance, let price = number("Kurs"), price > 0,
               let day = number("Perf. %"), let week = number("7 Tage %"),
               let month = number("1 Monat %"), let year = number("1 Jahr %") {
                metrics = DiscoveryMarketMetrics(price: price, change1dPercent: day,
                    change7dPercent: week, change30dPercent: month, change1yPercent: year)
            } else { metrics = nil }
            return WallstreetRankingEntry(path: link, name: MarketPageHTML.plainText(name),
                rank: rank, trades: kind == .wikifolio ? number("Trades").flatMap { (0...1_000_000_000).contains($0) ? Int($0) : nil } : nil, metrics: metrics)
        }
        guard !entries.isEmpty else { throw DiscoveryDataError.invalidCandidate }
        return entries.sorted { $0.rank < $1.rank }
    }
}
