import Foundation

struct RadarDailyHistory: Sendable {
    let bars: [MinuteBar]
    let provider: String
}

actor RadarDailyHistoryService {
    static let shared = RadarDailyHistoryService()
    private var cached: [String: (Date, RadarDailyHistory)] = [:]
    private var pending: [String: Task<RadarDailyHistory, Error>] = [:]
    private let yahoo: @Sendable (String) async throws -> [MinuteBar]
    private let fmp: @Sendable (String) async throws -> [MinuteBar]?

    init(yahoo: @escaping @Sendable (String) async throws -> [MinuteBar] = {
        try await YahooRadarSource().dailyBars(symbol: $0)
    }, fmp: @escaping @Sendable (String) async throws -> [MinuteBar]? = { symbol in
        guard let key = try ProviderCredentialStore.load(FMPCredential.account) else { return nil }
        return try await FMPHistoricalPriceSource().dailyBars(symbol: symbol, apiKey: key)
    }) {
        self.yahoo = yahoo
        self.fmp = fmp
    }

    func load(symbol: String, yahooEnabled: Bool = true, fmpEnabled: Bool = true) async throws -> RadarDailyHistory {
        let key = "\(symbol)|yahoo=\(yahooEnabled)|fmp=\(fmpEnabled)"
        if let (date, value) = cached[key], Date().timeIntervalSince(date) < 15 * 60 { return value }
        if let task = pending[key] { return try await task.value }
        let task = Task { [yahoo, fmp] in
            if yahooEnabled {
                do {
                    let bars = try await yahoo(symbol)
                    guard !bars.isEmpty else { throw DailyHistoryError.unavailable }
                    return RadarDailyHistory(bars: bars, provider: "Yahoo")
                } catch is CancellationError { throw CancellationError() }
                catch {
                    if fmpEnabled, let bars = try? await fmp(symbol), !bars.isEmpty {
                        return RadarDailyHistory(bars: bars, provider: "FMP")
                    }
                }
            } else if fmpEnabled, let bars = try? await fmp(symbol), !bars.isEmpty {
                return RadarDailyHistory(bars: bars, provider: "FMP")
            }
            throw DailyHistoryError.unavailable
        }
        pending[key] = task
        defer { pending[key] = nil }
        let value = try await task.value
        cached[key] = (Date(), value)
        AppDiagnostics.shared.record(.info, "RadarChart", "daily-history-loaded",
                                     "symbol=\(symbol) provider=\(value.provider) bars=\(value.bars.count)")
        return value
    }
}

enum DailyHistoryError: LocalizedError {
    case unavailable
    var errorDescription: String? { "Daily price history is temporarily unavailable. Try again later." }
}
