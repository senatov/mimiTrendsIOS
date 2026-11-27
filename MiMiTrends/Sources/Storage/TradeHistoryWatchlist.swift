import Foundation

struct TradeHistoryWatchEntry: Identifiable, Sendable {
    let id: String
    let name: String
    let symbol: String?
    let tradingDays: Int
    let latestTrade: Date
    let isPriority: Bool

    var radarSymbol: String? {
        symbol.flatMap { MarketCandidateFilter.supportsYahooBars(symbol: $0) ? $0 : nil }
    }
}

actor TradeHistoryWatchlist {
    static let shared = TradeHistoryWatchlist()
    static let excludedDiscoverySymbols: Set<String> = ["METC", "METCB", "CELC", "7VR.DE", "SNDX"]

    private var store: BrokerTransactionStore?
    private var symbols: [String: String] = [:]
    private var directory: [String: String] = [:]
    private var didReadCache = false
    private var nextDirectoryRefresh = Date.distantPast
    private var isResolving = false

    func load(candidates: [RadarCompanyCandidate] = [], now: Date = Date()) async throws -> [TradeHistoryWatchEntry] {
        if store == nil { store = try BrokerTransactionStore(url: BrokerTransactionStore.defaultURL()) }
        guard let store else { return [] }
        let trades = try await store.loadExecutedTransactions(since: Self.cutoff(now), through: now)
        let mappingURL = try BrokerTransactionStore.defaultURL().deletingLastPathComponent()
            .appendingPathComponent("mimitrends-trade-symbols.json")
        if !didReadCache {
            didReadCache = true
            if let data = try? Data(contentsOf: mappingURL),
               let cached = try? JSONDecoder().decode([String: String].self, from: data) {
                symbols = cached.compactMapValues { try? WatchlistStore.normalize($0) }
            }
        }
        for company in candidates {
            guard let isin = company.isin, symbols[isin] == nil,
                  !isin.hasPrefix("US") || !MarketCandidateFilter.isGermanSymbol(company.symbol)
            else { continue }
            symbols[isin] = company.symbol
        }
        let entries = Self.entries(from: trades, symbols: symbols.merging(directory) { saved, _ in saved }, now: now)
        if !isResolving, now >= nextDirectoryRefresh, entries.contains(where: { $0.symbol == nil }) {
            isResolving = true
            Task { await refreshDirectory(for: entries.map(\.id), cacheURL: mappingURL) }
        }
        return entries
    }

    private func refreshDirectory(for identifiers: [String], cacheURL: URL) async {
        defer { isResolving = false }
        async let germany = try? TradingViewVolatilitySource().loadISINDirectory(.germany)
        async let unitedStates = try? TradingViewVolatilitySource().loadISINDirectory(.unitedStates)
        let (german, us) = await (germany, unitedStates)
        directory.merge(german ?? [:]) { _, current in current }
        directory.merge(us ?? [:]) { _, current in current }
        for isin in identifiers where symbols[isin] == nil { symbols[isin] = directory[isin] }
        if let data = try? JSONEncoder().encode(symbols) {
            try? data.write(to: cacheURL, options: .atomic)
        }
        nextDirectoryRefresh = Date().addingTimeInterval(german != nil && us != nil ? 86_400 : 300)
    }

    static func cutoff(_ now: Date) -> Date {
        calendar.date(byAdding: .month, value: -4, to: calendar.startOfDay(for: now)) ?? now
    }

    static func entries(from trades: [BrokerTradeExecution], symbols: [String: String], now: Date)
        -> [TradeHistoryWatchEntry] {
        let start = Int64(cutoff(now).timeIntervalSince1970)
        let end = Int64(now.timeIntervalSince1970)
        let inWindow = trades.filter { (start...end).contains($0.occurredAtEpochSeconds) }
        let grouped = Dictionary(grouping: inWindow) { $0.isin ?? $0.description }
        return grouped.compactMap { key, executions -> TradeHistoryWatchEntry? in
            guard executions.contains(where: { $0.type.caseInsensitiveCompare("Buy") == .orderedSame }),
                  let latest = executions.max(by: { $0.occurredAtEpochSeconds < $1.occurredAtEpochSeconds })
            else { return nil }
            let dates = executions.map { Date(timeIntervalSince1970: Double($0.occurredAtEpochSeconds)) }
            let calendar = Self.calendar
            let days = Set(dates.map { calendar.startOfDay(for: $0) }).count
            let months = Set(dates.map { calendar.dateComponents([.year, .month], from: $0) }).count
            return TradeHistoryWatchEntry(id: key, name: latest.description, symbol: symbols[key],
                tradingDays: days, latestTrade: Date(timeIntervalSince1970: Double(latest.occurredAtEpochSeconds)),
                isPriority: days >= 5 && months >= 3)
        }.sorted {
            if $0.isPriority != $1.isPriority { return $0.isPriority }
            if $0.latestTrade != $1.latestTrade { return $0.latestTrade > $1.latestTrade }
            if $0.tradingDays != $1.tradingDays { return $0.tradingDays > $1.tradingDays }
            return $0.id < $1.id
        }
    }

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .gmt
        return calendar
    }
}
