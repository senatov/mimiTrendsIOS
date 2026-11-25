import Foundation

struct TradingViewVolatilityCandidate: Sendable {
    let company: RadarCompanyCandidate
    let score: Double
}

struct TradingViewVolatilitySource: Sendable {
    enum Market: Sendable { case germany, unitedStates }
    enum Ranking: Sendable, Equatable { case volatility, activity, strongRise, shortDrop(Int)

        var dropColumn: String? {
            if case .shortDrop(let minutes) = self { return "change|\(minutes)" }
            return nil
        } }

    private let session: URLSession

    init(session: URLSession = .shared) { self.session = session }

    func load(_ market: Market) async throws -> [TradingViewVolatilityCandidate] {
        do {
            let candidates = try await scan(market, ranking: .volatility)
            if !candidates.isEmpty { return candidates }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            AppDiagnostics.shared.record(.warning, "TradingView", "screener-unavailable",
                "market=\(market) error=\(String(describing: type(of: error))) fallback=page")
        }
        return try await loadPage(market)
    }

    func loadActive(_ market: Market) async throws -> [TradingViewVolatilityCandidate] {
        let candidates = try await scan(market, ranking: .activity)
        guard !candidates.isEmpty else { throw RadarSourceError.invalidResponse }
        return candidates
    }

    func loadStrongRisers(_ market: Market) async throws -> [TradingViewVolatilityCandidate] {
        try await scan(market, ranking: .strongRise)
    }

    func loadShortDrops(_ market: Market) async throws -> [TradingViewVolatilityCandidate] {
        async let five = scan(market, ranking: .shortDrop(5))
        async let fifteen = scan(market, ranking: .shortDrop(15))
        return try await (five + fifteen).sorted {
            $0.score == $1.score ? $0.company.symbol < $1.company.symbol : $0.score > $1.score
        }
    }

    private func loadPage(_ market: Market) async throws -> [TradingViewVolatilityCandidate] {
        let endpoint: ProviderEndpoint = market == .germany ? .tradingViewGermany : .tradingViewUS
        var request = URLRequest(url: ProviderEndpointStore.url(for: endpoint))
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await BrowserPageRequest.send(request, using: session)
        guard let response = response as? HTTPURLResponse else { throw RadarSourceError.invalidResponse }
        if response.statusCode == 429 { throw RadarSourceError.rateLimited }
        guard response.statusCode == 200 else { throw RadarSourceError.httpStatus(response.statusCode) }
        guard data.count <= 3_000_000, let html = String(data: data, encoding: .utf8) else {
            throw RadarSourceError.invalidResponse
        }
        let candidates = Self.parse(html, market: market)
        guard !candidates.isEmpty else { throw RadarSourceError.invalidResponse }
        return candidates
    }

    private func scan(_ market: Market, ranking: Ranking) async throws -> [TradingViewVolatilityCandidate] {
        let region = market == .germany ? "germany" : "america"
        let exchanges = market == .germany ? ["XETR"] : ["NASDAQ", "NYSE", "AMEX"]
        let strongTurnover = market == .germany ? 250_000 : 10_000_000
        let strongChange = market == .germany ? 5 : 10
        let dropColumn = ranking.dropColumn
        var candidates: [TradingViewVolatilityCandidate] = []
        for exchange in exchanges {
            try Task.checkCancellation()
            var request = URLRequest(url: URL(string: "https://scanner.tradingview.com/\(region)/scan")!)
            request.httpMethod = "POST"
            request.timeoutInterval = 20
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            var filters: [[String: Any]] = [["left": "type", "operation": "equal", "right": "stock"],
                           ["left": "exchange", "operation": "equal", "right": exchange],
                           ["left": "close", "operation": "egreater",
                            "right": ranking == .strongRise ? 2 : 5],
                           ["left": "market_cap_basic", "operation": "egreater",
                            "right": ranking == .strongRise ? 25_000_000 : 100_000_000],
                           ["left": "Value.Traded", "operation": "egreater",
                            "right": ranking == .strongRise ? strongTurnover :
                                (market == .germany ? 500_000 : 1_000_000)]]
            if ranking == .volatility {
                filters.append(["left": "relative_volume_10d_calc", "operation": "egreater",
                                "right": market == .germany ? 0.5 : 0.2])
            }
            if ranking == .strongRise {
                filters.append(["left": "change", "operation": "egreater", "right": strongChange])
            }
            if let dropColumn {
                filters.append(["left": dropColumn, "operation": "eless", "right": -0.8])
            }
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "filter": filters,
                "options": ["lang": "en"],
                "columns": ["name", "description", "exchange", "close", "volume",
                            "relative_volume_10d_calc", "market_cap_basic", "Volatility.D", "isin",
                            dropColumn ?? "change"],
                "sort": ["sortBy": dropColumn ?? (ranking == .activity ? "Value.Traded" : "Volatility.D"),
                         "sortOrder": dropColumn == nil ? "desc" : "asc"],
                "range": [0, dropColumn != nil ? 49 : ranking == .activity ? 149 : ranking == .strongRise ? 99 : 299]
            ] as [String: Any])
            let (data, response) = try await BrowserPageRequest.send(request, using: session)
            guard let response = response as? HTTPURLResponse, response.statusCode == 200,
                  data.count <= 3_000_000 else { throw RadarSourceError.invalidResponse }
            candidates += try Self.parseScanJSON(data, market: market, ranking: ranking)
        }
        return candidates.sorted {
            $0.score == $1.score ? $0.company.symbol < $1.company.symbol : $0.score > $1.score
        }
    }

    private struct ScanResponse: Decodable { let data: [ScanRow] }

    static func parseScanJSON(_ data: Data, market: Market,
                              ranking: Ranking = .volatility) throws -> [TradingViewVolatilityCandidate] {
        let result = try JSONDecoder().decode(ScanResponse.self, from: data)
        return select(result.data, market: market, ranking: ranking)
    }
    private struct ScanRow: Decodable {
        let s: String
        let d: [ScanValue]
    }
    private enum ScanValue: Decodable {
        case string(String), number(Double), other

        init(from decoder: Decoder) throws {
            let value = try decoder.singleValueContainer()
            if let number = try? value.decode(Double.self) { self = .number(number) }
            else if let string = try? value.decode(String.self) { self = .string(string) }
            else { self = .other }
        }
        var text: String? { if case .string(let value) = self { value } else { nil } }
        var number: Double? { if case .number(let value) = self { value } else { nil } }
    }

    private static func select(_ rows: [ScanRow], market: Market,
                               ranking: Ranking) -> [TradingViewVolatilityCandidate] {
        let strongTurnover = market == .germany ? 250_000.0 : 10_000_000.0
        let strongChange = market == .germany ? 5.0 : 10.0
        var seen = Set<String>()
        return rows.compactMap { row -> TradingViewVolatilityCandidate? in
            guard row.d.count >= 9, let name = row.d[1].text, let exchange = row.d[2].text,
                  let price = row.d[3].number, let volume = row.d[4].number,
                  let cap = row.d[6].number,
                  cap >= (ranking == .strongRise ? 25_000_000 : 100_000_000),
                  price * volume >= (ranking == .strongRise ? strongTurnover :
                    (market == .germany ? 500_000 : 1_000_000)) else { return nil }
            if ranking == .strongRise {
                guard row.d.count >= 10, (row.d[9].number ?? 0) >= strongChange else { return nil }
            }
            let change = row.d.count >= 10 ? row.d[9].number : nil
            if ranking.dropColumn != nil {
                guard let change, change <= -0.8 else { return nil }
            }
            let relativeVolume = row.d[5].number ?? 0
            let volatility = row.d[7].number ?? 0
            if ranking == .volatility {
                guard volatility >= 1,
                      relativeVolume >= (market == .germany ? 0.5 : 0.2) else { return nil }
            }
            let ticker = row.d[0].text?.uppercased() ?? ""
            let symbol: String
            switch market {
            case .germany:
                guard exchange == "XETR", row.s == "XETR:\(ticker)",
                      ticker.range(of: #"^[A-Z0-9]{1,10}$"#, options: .regularExpression) != nil else { return nil }
                symbol = ticker + ".DE"
            case .unitedStates:
                guard ["NASDAQ", "NYSE", "AMEX"].contains(exchange), row.s == "\(exchange):\(ticker)",
                      MarketCandidateFilter.supportsUSSymbol(ticker) else { return nil }
                symbol = ticker
            }
            guard seen.insert(symbol).inserted,
                  MarketCandidateFilter.accepts(symbol: symbol, name: name, price: price,
                    exchange: market == .germany ? "XETRA" : exchange,
                    currency: market == .germany ? "EUR" : "USD",
                    minimumPrice: ranking == .strongRise ? 2 : 5)
            else { return nil }
            let score: Double
            if ranking == .activity { score = price * volume }
            else if ranking == .strongRise { score = change ?? 0 }
            else if ranking.dropColumn != nil { score = -(change ?? 0) }
            else {
                score = min(volatility, 30) * sqrt(min(relativeVolume, 10))
                    * log10(max(10, price * volume))
            }
            let isin = row.d[8].text
            return TradingViewVolatilityCandidate(
                company: RadarCompanyCandidate(symbol: symbol, name: name, isin: isin), score: score)
        }.sorted { $0.score == $1.score ? $0.company.symbol < $1.company.symbol : $0.score > $1.score }
    }

    static func parse(_ html: String, market: Market) -> [TradingViewVolatilityCandidate] {
        let rows = MarketPageHTML.matches(#"<tbody\b[^>]*>(.*?)</tbody>"#, in: html)
            .flatMap { MarketPageHTML.matches(#"<tr\b[^>]*>(.*?)</tr>"#, in: $0) }
        var seen = Set<String>()
        return rows.compactMap { row -> TradingViewVolatilityCandidate? in
            let cells = MarketPageHTML.matches(#"<td\b[^>]*>(.*?)</td>"#, in: row)
            guard cells.count >= 7,
                  let path = MarketPageHTML.first(#"href="/symbols/([A-Z0-9]+-[A-Z0-9.-]+)/""#, in: cells[0]),
                  let separator = path.firstIndex(of: "-") else { return nil }
            let exchange = String(path[..<separator])
            let ticker = String(path[path.index(after: separator)...]).uppercased()
            let symbol: String
            switch market {
            case .germany:
                guard exchange == "XETR", ticker.range(of: #"^[A-Z0-9]{1,10}$"#, options: .regularExpression) != nil else { return nil }
                symbol = ticker + ".DE"
            case .unitedStates:
                guard ["NASDAQ", "NYSE", "AMEX"].contains(exchange),
                      MarketCandidateFilter.supportsUSSymbol(ticker) else { return nil }
                symbol = ticker
            }
            guard seen.insert(symbol).inserted,
                  let volatility = number(cells[1]), volatility >= 1,
                  let price = number(cells[2]), price >= 5,
                  let volume = number(cells[4]), volume > 0,
                  let relativeVolume = number(cells[5]),
                  relativeVolume >= (market == .germany ? 0.5 : 0.2),
                  let marketCap = number(cells[6]),
                  marketCap >= 100_000_000,
                  price * volume >= (market == .germany ? 500_000 : 1_000_000) else { return nil }
            let links = MarketPageHTML.matches(#"<a\b[^>]*href="/symbols/[^\"]+"[^>]*>(.*?)</a>"#, in: cells[0])
            let name = links.last.map(MarketPageHTML.plainText) ?? ticker
            guard MarketCandidateFilter.accepts(symbol: symbol, name: name, price: price,
                exchange: market == .germany ? "XETRA" : exchange,
                currency: market == .germany ? "EUR" : "USD") else { return nil }
            let score = min(volatility, 30) * sqrt(min(relativeVolume, 10))
                * log10(max(10, price * volume))
            return TradingViewVolatilityCandidate(
                company: RadarCompanyCandidate(symbol: symbol, name: name), score: score)
        }.sorted { $0.score == $1.score ? $0.company.symbol < $1.company.symbol : $0.score > $1.score }
    }

    private static func number(_ html: String) -> Double? {
        let text = MarketPageHTML.plainText(html)
            .replacingOccurrences(of: "\u{202f}", with: "")
            .replacingOccurrences(of: "\u{a0}", with: "")
            .replacingOccurrences(of: ",", with: "")
        guard let raw = MarketPageHTML.first(#"^\s*([0-9]+(?:\.[0-9]+)?\s*[KMBT]?)"#, in: text) else { return nil }
        let clean = raw.replacingOccurrences(of: " ", with: "")
        let scale: Double
        switch clean.last {
        case "K": scale = 1_000
        case "M": scale = 1_000_000
        case "B": scale = 1_000_000_000
        case "T": scale = 1_000_000_000_000
        default: scale = 1
        }
        let digits = scale == 1 ? clean : String(clean.dropLast())
        return Double(digits).map { $0 * scale }
    }
}
