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
}

struct MarketScanProgress: Sendable, Equatable {
    let processed: Int
    let total: Int
    let successful: Int
    let skipped: Int
    let noRecentBars: Int
    let unsupported: Int
    let errors: Int
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
