import Foundation

struct RadarSourceTotals: Sendable {
    var received = 0
    var valid = 0
    var operations = 0
    var errors = 0
    var lastErrorMessage: String?
}

struct MarketRadarCycle: Sendable {
    let yahoo: RadarSourceTotals
    let traderFox: RadarSourceTotals
    let fmp: RadarSourceTotals
    let usesFMP: Bool
    let yahooCooldownUntil: Date?
    let initialScanProcessed: Int
    let initialScanTotal: Int
    let scannedSymbols: Int
    let companyNames: [String: String]
    let progress: MarketScanProgress
    var candidates: [RadarCompanyCandidate] = []
}

struct MarketScanProgress: Sendable, Equatable {
    let processed: Int
    let total: Int
    let successful: Int
    let skipped: Int
    let noRecentBars: Int
    let unsupported: Int
    let errors: Int
    let issues: [String]
    let activeSymbols: [String]
    let lastUpdatedAt: Date?
}

enum MarketRadarErrorDescription {
    static func message(_ error: Error, provider: String) -> String {
        if let sourceError = error as? RadarSourceError {
            switch sourceError {
            case .rateLimited:
                return "\(provider) temporarily limited requests (HTTP 429). Radar will retry after its cooldown."
            case .httpStatus(let status) where status == 401 || status == 403:
                return "\(provider) denied access (HTTP \(status)). Check that the source address is correct and that the provider permits requests from this app."
            case .httpStatus(let status) where status >= 500:
                return "\(provider) returned a server error (HTTP \(status)). This is usually temporary; Radar retries automatically."
            case .httpStatus(let status):
                return "\(provider) returned HTTP \(status). Check provider availability and the configured address."
            case .invalidResponse:
                return "\(provider) returned data in a format Radar could not read. The page or response format may have changed."
            case .invalidSymbol:
                return "\(provider) does not support this symbol. Radar skips unsupported symbols automatically."
            }
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut:
                return "The request to \(provider) timed out. Check the internet connection or try again later."
            case .notConnectedToInternet, .networkConnectionLost:
                return "The device could not reach \(provider). Check the internet connection; Radar retries automatically."
            case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
                return "The device could not connect to \(provider). Check the configured address or try again later."
            default:
                return "The request to \(provider) failed: \(urlError.localizedDescription)"
            }
        }
        return "The request to \(provider) failed (\(String(describing: type(of: error)))). Check the network and retry; Radar retries automatically."
    }
}
import Foundation

struct YahooSymbolEvidence: Sendable {
    let symbol: String
    let found: Bool
    let name: String?
    let currency: String?
    let exchange: String?
    let detail: String
}

struct YahooSymbolResolution: Codable, Sendable {
    let symbol: String
    let summary: String
    let providerEvidence: [String]
    let checkedAtMillis: Int64
    let retryAfterMillis: Int64
}

private struct SecondarySymbolEvidence: Sendable {
    let matched: Bool
    let detail: String
}

actor YahooSymbolResolutionStore {
    static let shared = YahooSymbolResolutionStore()
    private let defaults = UserDefaults.standard
    private let key = "radar.yahoo-symbol-resolutions.v1"
    private var resolutions: [String: YahooSymbolResolution]

    private init() {
        if let data = UserDefaults.standard.data(forKey: "radar.yahoo-symbol-resolutions.v1"),
           let saved = try? JSONDecoder().decode([String: YahooSymbolResolution].self, from: data) {
            resolutions = saved
        } else {
            resolutions = [:]
        }
    }

    func skippedSymbols(nowMillis: Int64 = Int64(Date().timeIntervalSince1970 * 1_000)) -> Set<String> {
        Set(resolutions.values.filter { $0.retryAfterMillis > nowMillis }.map(\.symbol))
    }

    func save(_ resolution: YahooSymbolResolution) {
        resolutions[resolution.symbol] = resolution
        let cutoff = resolution.checkedAtMillis - 60 * 24 * 60 * 60 * 1_000
        resolutions = resolutions.filter { $0.value.checkedAtMillis >= cutoff }
        if let data = try? JSONEncoder().encode(resolutions) { defaults.set(data, forKey: key) }
    }
}

struct YahooSymbolDiagnosisService: Sendable {
    private let session: URLSession

    init(session: URLSession = .shared) { self.session = session }

    func diagnose(symbol rawSymbol: String) async -> YahooSymbolResolution {
        let symbol = rawSymbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let checkedAt = Int64(Date().timeIntervalSince1970 * 1_000)
        let yahoo = await YahooRadarSource(session: session).diagnose(symbol: symbol)
        var evidence = ["Yahoo: \(yahoo.detail)"]
        var independentMatches: [String] = []
        let fmpEnabled = MarketProviderAccess.isEnabled(.fmp)
        let finnhubEnabled = MarketProviderAccess.isEnabled(.finnhub)
        let fmpKey = fmpEnabled ? try? ProviderCredentialStore.load(FMPCredential.account) : nil
        let finnhubKey = finnhubEnabled ? try? FinnhubCredentialStore.load() : nil
        async let fmpEvidence = lookupFMP(symbol: symbol, apiKey: fmpKey)
        async let finnhubEvidence = lookupFinnhub(symbol: symbol, apiKey: finnhubKey)
        if let fmp = await fmpEvidence {
            evidence.append("FMP: \(fmp.detail)")
            if fmp.matched { independentMatches.append("FMP") }
        } else {
            evidence.append(fmpEnabled ? "FMP: not queried (API key is not configured)." : "FMP: not checked (provider disabled).")
        }
        if let finnhub = await finnhubEvidence {
            evidence.append("Finnhub: \(finnhub.detail)")
            if finnhub.matched { independentMatches.append("Finnhub") }
        } else {
            evidence.append(finnhubEnabled ? "Finnhub: not queried (API key is not configured)." : "Finnhub: not checked (provider disabled).")
        }

        let summary: String
        let retryDelay: Int64
        if yahoo.found {
            summary = "Auto-check confirms Yahoo recognizes \(symbol), but its minute response did not match Radar's expected format. \(independentMatches.isEmpty ? "" : "Also confirmed by \(independentMatches.joined(separator: " and ")).") Rechecking in 24 hours."
            retryDelay = 24 * 60 * 60 * 1_000
        } else if !independentMatches.isEmpty {
            summary = "Auto-check confirms \(symbol) with \(independentMatches.joined(separator: " and ")), but Yahoo returned no usable instrument metadata. Rechecking in 24 hours."
            retryDelay = 24 * 60 * 60 * 1_000
        } else {
            summary = "Auto-check could not confirm \(symbol) with any queried source. Temporarily skipped; rechecking in 6 hours."
            retryDelay = 6 * 60 * 60 * 1_000
        }
        return YahooSymbolResolution(symbol: symbol, summary: summary, providerEvidence: evidence,
                                     checkedAtMillis: checkedAt, retryAfterMillis: checkedAt + retryDelay)
    }

    private func fmpMatch(symbol: String, apiKey: String) async -> SecondarySymbolEvidence {
        guard var components = URLComponents(string: "https://financialmodelingprep.com/stable/search-symbol") else {
            return SecondarySymbolEvidence(matched: false, detail: "lookup URL could not be created.")
        }
        components.queryItems = [URLQueryItem(name: "query", value: symbol),
                                 URLQueryItem(name: "apikey", value: apiKey)]
        guard let url = components.url else { return SecondarySymbolEvidence(matched: false, detail: "lookup URL could not be created.") }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return SecondarySymbolEvidence(matched: false, detail: "invalid HTTP response.")
            }
            guard http.statusCode == 200 else {
                return SecondarySymbolEvidence(matched: false, detail: "lookup unavailable (HTTP \(http.statusCode)).")
            }
            guard data.count <= 500_000,
                  let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                return SecondarySymbolEvidence(matched: false, detail: "lookup returned unreadable JSON.")
            }
            guard let row = rows.first(where: { ($0["symbol"] as? String)?.caseInsensitiveCompare(symbol) == .orderedSame }) else {
                return SecondarySymbolEvidence(matched: false, detail: "no exact-symbol match.")
            }
            let name = row["name"] as? String ?? "name unavailable"
            let currency = row["currency"] as? String ?? "currency unavailable"
            let exchange = row["exchangeFullName"] as? String ?? row["exchange"] as? String ?? "exchange unavailable"
            return SecondarySymbolEvidence(matched: true, detail: "exact match: \(name), \(exchange), \(currency).")
        } catch { return SecondarySymbolEvidence(matched: false, detail: "lookup failed: \(error.localizedDescription)") }
    }

    private func lookupFMP(symbol: String, apiKey: String?) async -> SecondarySymbolEvidence? {
        guard let apiKey else { return nil }
        return await fmpMatch(symbol: symbol, apiKey: apiKey)
    }

    private func finnhubMatch(symbol: String, apiKey: String) async -> SecondarySymbolEvidence {
        guard var components = URLComponents(string: "https://finnhub.io/api/v1/stock/profile2") else {
            return SecondarySymbolEvidence(matched: false, detail: "profile URL could not be created.")
        }
        components.queryItems = [URLQueryItem(name: "symbol", value: symbol)]
        guard let url = components.url else { return SecondarySymbolEvidence(matched: false, detail: "profile URL could not be created.") }
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "X-Finnhub-Token")
        request.timeoutInterval = 10
        request.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return SecondarySymbolEvidence(matched: false, detail: "invalid HTTP response.")
            }
            guard http.statusCode == 200 else {
                return SecondarySymbolEvidence(matched: false, detail: "profile unavailable (HTTP \(http.statusCode)).")
            }
            guard data.count <= 100_000,
                  let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return SecondarySymbolEvidence(matched: false, detail: "profile returned unreadable JSON.")
            }
            guard (object["ticker"] as? String)?.caseInsensitiveCompare(symbol) == .orderedSame else {
                return SecondarySymbolEvidence(matched: false, detail: "no exact-symbol profile.")
            }
            let name = object["name"] as? String ?? "name unavailable"
            let currency = object["currency"] as? String ?? "currency unavailable"
            let exchange = object["exchange"] as? String ?? "exchange unavailable"
            return SecondarySymbolEvidence(matched: true, detail: "exact profile: \(name), \(exchange), \(currency).")
        } catch { return SecondarySymbolEvidence(matched: false, detail: "profile request failed: \(error.localizedDescription)") }
    }

    private func lookupFinnhub(symbol: String, apiKey: String?) async -> SecondarySymbolEvidence? {
        guard let apiKey else { return nil }
        return await finnhubMatch(symbol: symbol, apiKey: apiKey)
    }
}
