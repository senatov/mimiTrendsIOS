import Foundation

struct YahooRadarSource: Sendable {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func mostActiveCandidates(limit: Int = 20) async throws -> [RadarCompanyCandidate] {
        let path = "/v1/finance/screener/predefined/saved?scrIds=most_actives&count=50&start=0"
        let root = try await loadWithFallback(path: path)
        guard let finance = root["finance"] as? [String: Any],
              let result = finance["result"] as? [[String: Any]],
              let quotes = result.first?["quotes"] as? [[String: Any]] else {
            throw RadarSourceError.invalidResponse
        }
        return Self.activeCandidates(in: quotes, limit: limit)
    }

    func minuteBars(symbol: String) async throws -> [MinuteBar] {
        guard FinnhubBidAskClient.supports(symbol: symbol),
              let encoded = symbol.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              !encoded.isEmpty else {
            throw RadarSourceError.invalidSymbol
        }
        let path = "/v8/finance/chart/\(encoded)?range=1d&interval=1m&includePrePost=false"
        return try Self.decodeBars(try await loadWithFallback(path: path), symbol: symbol)
    }

    private func loadWithFallback(path: String) async throws -> [String: Any] {
        let primary = URL(string: path, relativeTo: ProviderEndpointStore.url(for: .yahooPrimary))!.absoluteURL
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
            let alternate = URL(string: path, relativeTo: ProviderEndpointStore.url(for: .yahooAlternate))!.absoluteURL
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
                  FinnhubBidAskClient.supports(symbol: symbol),
                  let volume = (quote["regularMarketVolume"] as? NSNumber)?.doubleValue,
                  volume > 0, seen.insert(symbol).inserted else { return nil }
            let name = (quote["shortName"] as? String) ?? (quote["longName"] as? String) ?? symbol
            return (RadarCompanyCandidate(symbol: symbol, name: name), volume)
        }
        .sorted { $0.1 > $1.1 }
        .prefix(max(0, limit))
        .map(\.0)
    }

    static func decodeBars(_ root: [String: Any], symbol: String) throws -> [MinuteBar] {
        guard let chart = root["chart"] as? [String: Any],
              let result = chart["result"] as? [[String: Any]],
              let first = result.first,
              let meta = first["meta"] as? [String: Any],
              meta["currency"] as? String == "USD",
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
        guard count <= 600 else { throw RadarSourceError.invalidResponse }
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

enum RadarSourceError: Error {
    case invalidResponse
    case invalidSymbol
    case rateLimited
    case httpStatus(Int)
}
