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
    let yahooCooldownUntil: Date?
    let initialScanProcessed: Int
    let initialScanTotal: Int
    let scannedSymbols: Int
    let companyNames: [String: String]
    let progress: MarketScanProgress
    var candidates: [RadarCompanyCandidate] = []

    func reporting(_ scan: MarketScanProgress, cooldown: Date?) -> Self {
        Self(yahoo: yahoo, traderFox: traderFox, yahooCooldownUntil: cooldown,
             initialScanProcessed: scan.processed, initialScanTotal: scan.total,
             scannedSymbols: scan.successful, companyNames: companyNames,
             progress: scan, candidates: candidates)
    }
}

struct MarketScanProgress: Sendable, Equatable {
    let processed: Int
    let total: Int
    let successful: Int
    let skipped: Int
    let noRecentBars: Int
    let noReportedVolume: Int
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
        let evidence = ["Yahoo: \(yahoo.detail)"]

        let summary: String
        let retryDelay: Int64
        if yahoo.found {
            summary = "Auto-check confirms Yahoo recognizes \(symbol), but its minute response did not match Radar's expected format. Rechecking in 24 hours."
            retryDelay = 24 * 60 * 60 * 1_000
        } else {
            summary = "Auto-check could not confirm \(symbol) with any queried source. Temporarily skipped; rechecking in 6 hours."
            retryDelay = 6 * 60 * 60 * 1_000
        }
        return YahooSymbolResolution(symbol: symbol, summary: summary, providerEvidence: evidence,
                                     checkedAtMillis: checkedAt, retryAfterMillis: checkedAt + retryDelay)
    }

}
