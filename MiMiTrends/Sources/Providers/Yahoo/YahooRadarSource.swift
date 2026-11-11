import Foundation

enum YahooAPIEndpoint {
    static let primary = URL(string: "https://query1.finance.yahoo.com")!
    static let alternate = URL(string: "https://query2.finance.yahoo.com")!
}

struct YahooRadarSource: Sendable {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func mostActiveCandidates(limit: Int = 20) async throws -> [RadarCompanyCandidate] {
        let primary = ProviderEndpointStore.url(for: .yahooPrimary)
        do {
            return try await YahooRankingPageSource(session: session)
                .loadCandidates(from: primary, limit: limit)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            let alternate = ProviderEndpointStore.url(for: .yahooAlternate)
            guard alternate != primary else { throw error }
            return try await YahooRankingPageSource(session: session)
                .loadCandidates(from: alternate, limit: limit)
        }
    }

    func minuteBars(symbol: String, includeExtendedHours: Bool = false) async throws -> [MinuteBar] {
        guard MarketCandidateFilter.supportsYahooBars(symbol: symbol),
              let encoded = symbol.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              !encoded.isEmpty else {
            throw RadarSourceError.invalidSymbol
        }
        let path = "/v8/finance/chart/\(encoded)?range=1d&interval=1m&includePrePost=\(includeExtendedHours)"
        let root = try await loadWithFallback(path: path)
        guard let chart = root["chart"] as? [String: Any],
              let result = (chart["result"] as? [[String: Any]])?.first,
              let meta = result["meta"] as? [String: Any],
              (meta["symbol"] as? String)?.caseInsensitiveCompare(symbol) == .orderedSame else {
            throw RadarSourceError.invalidResponse
        }
        return try Self.decodeBars(root, symbol: symbol, maximumBars: includeExtendedHours ? 1_500 : 600)
    }

    func diagnose(symbol: String) async -> YahooSymbolEvidence {
        guard MarketCandidateFilter.supportsYahooBars(symbol: symbol),
              let encoded = symbol.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            return YahooSymbolEvidence(symbol: symbol, found: false, name: nil, currency: nil,
                                      exchange: nil, detail: "Symbol format is not supported by Yahoo.")
        }
        let path = "/v8/finance/chart/\(encoded)?range=1d&interval=1m&includePrePost=false"
        do {
            let root = try await loadWithFallback(path: path)
            guard let chart = root["chart"] as? [String: Any] else {
                return YahooSymbolEvidence(symbol: symbol, found: false, name: nil, currency: nil,
                                          exchange: nil, detail: "Yahoo response has no chart object.")
            }
            if let error = chart["error"], !(error is NSNull) {
                return YahooSymbolEvidence(symbol: symbol, found: false, name: nil, currency: nil,
                                          exchange: nil, detail: "Yahoo chart error: \(String(describing: error))")
            }
            guard let result = (chart["result"] as? [[String: Any]])?.first,
                  let meta = result["meta"] as? [String: Any] else {
                return YahooSymbolEvidence(symbol: symbol, found: false, name: nil, currency: nil,
                                          exchange: nil, detail: "Yahoo returned no instrument metadata.")
            }
            let providerSymbol = meta["symbol"] as? String
            let name = meta["longName"] as? String ?? meta["shortName"] as? String
            let currency = meta["currency"] as? String
            let exchange = meta["fullExchangeName"] as? String ?? meta["exchangeName"] as? String
            let timestamps = result["timestamp"] as? [Any] ?? []
            let rows = (result["indicators"] as? [String: Any])?["quote"] as? [[String: Any]]
            let closes = rows?.first?["close"] as? [Any] ?? []
            let usableBars = zip(timestamps, closes).reduce(into: 0) { count, pair in
                if !(pair.1 is NSNull), (pair.1 as? NSNumber)?.doubleValue != nil { count += 1 }
            }
            let detail = "Yahoo identifies \(providerSymbol ?? "no exact symbol"); \(name ?? "company name unavailable"); currency \(currency ?? "unknown"); \(exchange ?? "exchange unknown"); usable minute bars \(usableBars)."
            return YahooSymbolEvidence(symbol: providerSymbol ?? symbol,
                                       found: providerSymbol?.caseInsensitiveCompare(symbol) == .orderedSame, name: name,
                                       currency: currency, exchange: exchange, detail: detail)
        } catch {
            return YahooSymbolEvidence(symbol: symbol, found: false, name: nil, currency: nil,
                                      exchange: nil, detail: MarketRadarErrorDescription.message(error, provider: "Yahoo diagnostic"))
        }
    }

    func dailyBars(symbol: String) async throws -> [MinuteBar] {
        guard MarketCandidateFilter.supportsYahooBars(symbol: symbol),
              let encoded = symbol.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            throw RadarSourceError.invalidSymbol
        }
        // Two years provide EMA warm-up before the visible one-year window.
        let path = "/v8/finance/chart/\(encoded)?range=2y&interval=1d&includePrePost=false"
        return try Self.decodeBars(try await loadWithFallback(path: path), symbol: symbol)
    }

    func historicalMinuteBars(symbol: String, from: Int64, through: Int64) async throws -> [MinuteBar] {
        guard MarketCandidateFilter.supportsYahooBars(symbol: symbol), through > from,
              through - from <= 86_400,
              let encoded = symbol.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            throw RadarSourceError.invalidSymbol
        }
        let path = "/v8/finance/chart/\(encoded)?period1=\(from)&period2=\(through)&interval=1m&includePrePost=true"
        return try Self.decodeBars(try await loadWithFallback(path: path), symbol: symbol, maximumBars: 1_500)
    }

    private func loadWithFallback(path: String) async throws -> [String: Any] {
        let primary = URL(string: path, relativeTo: YahooAPIEndpoint.primary)!.absoluteURL
        do {
            return try await loadJSON(primary)
        } catch is CancellationError {
            throw CancellationError()
        } catch RadarSourceError.rateLimited {
            throw RadarSourceError.rateLimited
        } catch RadarSourceError.invalidSymbol {
            throw RadarSourceError.invalidSymbol
        } catch let RadarSourceError.httpStatus(status) where status < 500 {
            throw RadarSourceError.httpStatus(status)
        } catch {
            let alternate = URL(string: path, relativeTo: YahooAPIEndpoint.alternate)!.absoluteURL
            return try await loadJSON(alternate)
        }
    }

    private func loadJSON(_ url: URL) async throws -> [String: Any] {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("MiMiTrends/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw RadarSourceError.invalidResponse
        }
        if response.statusCode == 429 { throw RadarSourceError.rateLimited }
        if response.statusCode == 404 { throw RadarSourceError.invalidSymbol }
        guard response.statusCode == 200 else {
            throw RadarSourceError.httpStatus(response.statusCode)
        }
        guard data.count <= 2_000_000,
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw RadarSourceError.invalidResponse
        }
        return root
    }

    static func activeSymbols(in quotes: [[String: Any]], limit: Int) -> [String] {
        activeCandidates(in: quotes, limit: limit).map(\.symbol)
    }

    static func activeCandidates(in quotes: [[String: Any]], limit: Int) -> [RadarCompanyCandidate] {
        var seen = Set<String>()
        return quotes.compactMap { quote -> (RadarCompanyCandidate, Double)? in
            guard quote["quoteType"] as? String == "EQUITY",
                  let symbol = quote["symbol"] as? String,
                  MarketCandidateFilter.supportsYahooBars(symbol: symbol),
                  let volume = (quote["regularMarketVolume"] as? NSNumber)?.doubleValue,
                  let price = (quote["regularMarketPrice"] as? NSNumber)?.doubleValue,
                  let exchange = quote["exchange"] as? String else { return nil }
            let name = (quote["shortName"] as? String) ?? (quote["longName"] as? String) ?? symbol
            guard MarketCandidateFilter.accepts(
                symbol: symbol, name: name, price: price, exchange: exchange,
                currency: quote["currency"] as? String, volume: volume,
                marketCap: (quote["marketCap"] as? NSNumber)?.doubleValue
            ), seen.insert(symbol).inserted else { return nil }
            return (RadarCompanyCandidate(symbol: symbol, name: name), volume)
        }
        .sorted { $0.1 > $1.1 }
        .prefix(max(0, limit))
        .map(\.0)
    }

    static func decodeBars(_ root: [String: Any], symbol: String, maximumBars: Int = 600) throws -> [MinuteBar] {
        guard let chart = root["chart"] as? [String: Any],
              let result = chart["result"] as? [[String: Any]],
              let first = result.first,
              let meta = first["meta"] as? [String: Any],
              meta["currency"] as? String == (symbol.uppercased().hasSuffix(".DE") ? "EUR" : "USD"),
              let timestamps = first["timestamp"] as? [NSNumber],
              let indicators = first["indicators"] as? [String: Any],
              let quotes = indicators["quote"] as? [[String: Any]],
              let quote = quotes.first,
              let opens = quote["open"] as? [Any],
              let highs = quote["high"] as? [Any],
              let lows = quote["low"] as? [Any],
              let closes = quote["close"] as? [Any],
              let volumes = quote["volume"] as? [Any] else {
            throw RadarSourceError.invalidResponse
        }
        let count = min(timestamps.count, opens.count, highs.count, lows.count, closes.count, volumes.count)
        guard count <= maximumBars else { throw RadarSourceError.invalidResponse }
        return (0..<count).compactMap { index in
            guard let open = (opens[index] as? NSNumber)?.doubleValue,
                  let high = (highs[index] as? NSNumber)?.doubleValue,
                  let low = (lows[index] as? NSNumber)?.doubleValue,
                  let close = (closes[index] as? NSNumber)?.doubleValue else { return nil }
            let reported = (volumes[index] as? NSNumber)?.doubleValue
            let bar = MinuteBar(
                symbol: symbol,
                minuteEpochSeconds: timestamps[index].int64Value / 60 * 60,
                open: open, high: high, low: low, close: close,
                volume: reported ?? 0,
                volumeStatus: reported == nil ? .missing : reported == 0 ? .zero : .reported
            )
            return bar.isValid ? bar : nil
        }
    }
}

struct RadarCompanyCandidate: Sendable {
    let symbol: String
    let name: String
}

enum RadarSourceError: LocalizedError {
    case invalidResponse
    case invalidSymbol
    case rateLimited
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "The provider returned no readable market data."
        case .invalidSymbol: "The requested symbol was not found."
        case .rateLimited: "The provider limited requests (HTTP 429). Try again later."
        case .httpStatus(let status): "The provider returned HTTP \(status)."
        }
    }
}
