import Foundation

struct TradeHistoryWatchEntry: Identifiable, Sendable {
    let id: String
    let name: String
    let symbol: String?
    let tradingDays: Int
    let latestTrade: Date
    let isPriority: Bool
    var fcfYield: Double? = nil

    var radarSymbol: String? {
        symbol.flatMap { MarketCandidateFilter.supportsYahooBars(symbol: $0) ? $0 : nil }
    }
}

actor TradeHistoryWatchlist {
    static let shared = TradeHistoryWatchlist()
    struct Snapshot: Sendable {
        let entries: [TradeHistoryWatchEntry]
        let fcfYields: [String: Double]
    }

    private var store: BrokerTransactionStore?
    private var symbols: [String: String] = [:]
    private var germanDirectory = TradingViewVolatilitySource.ListingDirectory()
    private var usDirectory = TradingViewVolatilitySource.ListingDirectory()
    private var didReadCache = false
    private var nextDirectoryRefresh = Date.distantPast
    private var isResolving = false

    func load(candidates: [RadarCompanyCandidate] = [], useTradingView: Bool, now: Date = Date()) async throws -> Snapshot {
        if store == nil { store = try BrokerTransactionStore(url: BrokerTransactionStore.defaultURL()) }
        guard let store else { return Snapshot(entries: [], fcfYields: [:]) }
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
        let directory = germanDirectory.symbolsByISIN.merging(usDirectory.symbolsByISIN) { _, us in us }
        let yields = useTradingView ? germanDirectory.fcfYields.merging(usDirectory.fcfYields) { _, us in us } : [:]
        let entries = Self.entries(from: trades, symbols: symbols.merging(directory) { saved, _ in saved }, now: now)
        if useTradingView, !isResolving, now >= nextDirectoryRefresh {
            isResolving = true
            Task { await refreshDirectory(for: entries.map(\.id), cacheURL: mappingURL) }
        }
        return Snapshot(entries: Self.rank(entries, fcfYields: yields), fcfYields: yields)
    }

    private func refreshDirectory(for identifiers: [String], cacheURL: URL) async {
        defer { isResolving = false }
        async let germany = try? TradingViewVolatilitySource().loadISINDirectory(.germany)
        async let unitedStates = try? TradingViewVolatilitySource().loadISINDirectory(.unitedStates)
        let (german, us) = await (germany, unitedStates)
        if let german { germanDirectory = german }
        if let us { usDirectory = us }
        let directory = germanDirectory.symbolsByISIN.merging(usDirectory.symbolsByISIN) { _, us in us }
        for isin in identifiers where symbols[isin] == nil { symbols[isin] = directory[isin] }
        if let data = try? JSONEncoder().encode(symbols) {
            try? data.write(to: cacheURL, options: .atomic)
        }
        nextDirectoryRefresh = Date().addingTimeInterval(german != nil && us != nil ? 3_600 : 300)
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

    /// Input order is the history rank. Blend within each existing priority group.
    static func rank(_ entries: [TradeHistoryWatchEntry], fcfYields: [String: Double]) -> [TradeHistoryWatchEntry] {
        [entries.filter(\.isPriority), entries.filter { !$0.isPriority }].flatMap { group in
            group.enumerated().map { index, original in
                var entry = original
                entry.fcfYield = entry.symbol.flatMap { fcfYields[$0] }
                let history = 1 - Double(index) / Double(max(1, group.count - 1))
                let financial = min(0.10, max(-0.10, entry.fcfYield ?? 0)) / 0.20 + 0.5
                return (entry: entry, score: 0.8 * history + 0.2 * financial)
            }.sorted { $0.score > $1.score }.map(\.entry)
        }
    }

    static func rankDiscovery(_ symbols: [String], fcfYields: [String: Double]) -> [String] {
        // Preserve the market ranking among candidates with the same cash-flow category.
        func category(_ symbol: String) -> Int {
            let yield = fcfYields[symbol] ?? 0
            return yield > 0 ? 2 : yield < 0 ? 0 : 1
        }
        return symbols.sorted { category($0) > category($1) }
    }

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .gmt
        return calendar
    }
}
