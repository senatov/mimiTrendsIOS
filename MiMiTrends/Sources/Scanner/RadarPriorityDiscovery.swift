import Foundation

extension MarketRadarScanner {
    func refreshDrops(_ sessions: RadarTradingSessions) async {
        let source = TradingViewVolatilitySource()
        nextDropRefreshAt = Date().addingTimeInterval(60)
        async let us = sessions.us == .regular ? Self.loadDrops(source, market: .unitedStates) : []
        async let de = sessions.german == .regular ? Self.loadDrops(source, market: .germany) : []
        var seen = Set<String>()
        dropCandidates = await (us + de).sorted {
            $0.score == $1.score ? $0.company.symbol < $1.company.symbol : $0.score > $1.score
        }.map(\.company).filter { seen.insert($0.symbol).inserted }
    }

    private static func loadDrops(_ source: TradingViewVolatilitySource,
                                  market: TradingViewVolatilitySource.Market) async -> [TradingViewVolatilityCandidate] {
        do {
            let candidates = try await source.loadShortDrops(market)
            AppDiagnostics.shared.record(.info, "TradingView", "short-drop-candidates-loaded",
                "market=\(market) selected=\(candidates.count)")
            return candidates
        } catch {
            if !Task.isCancelled {
                AppDiagnostics.shared.record(.warning, "TradingView", "short-drop-refresh-failed",
                    "market=\(market) error=\(String(describing: error))")
            }
            return []
        }
    }

    func loadWatchlist() async -> [String] {
        do {
            if watchlistStore == nil {
                watchlistStore = try WatchlistStore(url: WatchlistStore.defaultURL())
            }
            return try await watchlistStore?.load().map(\.symbol) ?? []
        } catch {
            AppDiagnostics.shared.record(.warning, "Radar", "watchlist-load-failed",
                "error=\(String(describing: error))")
            return []
        }
    }

    func loadRecentPurchases(candidates: [RadarCompanyCandidate]) async -> [TradeHistoryWatchEntry] {
        do { return try await TradeHistoryWatchlist.shared.load(candidates: candidates) }
        catch {
            AppDiagnostics.shared.record(.warning, "Radar", "trade-history-watchlist-load-failed",
                                         "error=\(String(describing: error))")
            return []
        }
    }

    func logPriority(watchlist: [String], pool: [String], drops: [RadarCompanyCandidate],
                     verified: Set<String>) {
        let watched = Set(watchlist)
        let included = Set(pool)
        let candidates = watched.union(drops.map(\.symbol))
        var reported: [String: String] = [:]
        for symbol in candidates.sorted() {
            let source = watched.contains(symbol) ? "watchlist" : "short-drop"
            let eix = verified.contains(symbol) ? "verified" : "unverified"
            let status = "source=\(source) screenerEIX=\(eix) inPool=\(included.contains(symbol))"
            reported[symbol] = status
            if reportedPriority[symbol] != status {
                AppDiagnostics.shared.record(.info, "Radar", "priority-candidate",
                    "symbol=\(symbol) \(status)")
            }
        }
        reportedPriority = reported
    }
}
