import Foundation

struct RankingSourceHealth: Sendable {
    let kind: WallstreetRankingKind
    let enabled: Bool
    let count: Int
    let lastSuccess: Date?
    let failed: Bool
}

/// Both Radar discovery and the scan pool share one refresh and instrument list.
actor WallstreetDiscoverySource: DiscoveryCandidateSource {
    static let shared = WallstreetDiscoverySource()
    nonisolated let sourceID = "wallstreet_rankings"
    private let page = WallstreetRankingPageSource()
    private var entries: [WallstreetRankingKind: [WallstreetRankingEntry]] = [:]
    private var successes: [WallstreetRankingKind: Date] = [:]
    private var failures = Set<WallstreetRankingKind>()
    private var preferences: RadarDiscoveryPreferences?
    private var nextRefresh = Date.distantPast
    private var candidates: [DiscoveryCandidate] = []
    private var pending: Task<[DiscoveryCandidate], Error>?
    private var pendingPreferences: RadarDiscoveryPreferences?

    func loadCandidates() async throws -> [DiscoveryCandidate] {
        let settings = RadarDiscoveryPreferences.load()
        if let previous = preferences, Date() < nextRefresh, !candidates.isEmpty,
           previous.wikifolio == settings.wikifolio, previous.performance == settings.performance,
           previous.endpointSignature == settings.endpointSignature {
            if previous.priority != settings.priority {
                candidates = Self.merge(wikifolio: settings.wikifolio ? entries[.wikifolio] ?? [] : [],
                    performance: settings.performance ? entries[.performance] ?? [] : [],
                    settings: settings, observedAt: successes)
                preferences = settings
            }
            return candidates
        }
        if let pending, pendingPreferences == settings { return try await pending.value }
        pending?.cancel()
        let task = Task { try await refresh(settings: settings) }
        pending = task
        pendingPreferences = settings
        defer {
            if pendingPreferences == settings { pending = nil; pendingPreferences = nil }
        }
        return try await task.value
    }

    func refreshIntervalMillis() -> Int64 { failures.isEmpty ? 1_800_000 : 300_000 }

    func health() -> [RankingSourceHealth] {
        let settings = RadarDiscoveryPreferences.load()
        return WallstreetRankingKind.allCases.map { kind in
            RankingSourceHealth(kind: kind, enabled: kind == .wikifolio ? settings.wikifolio : settings.performance,
                                count: entries[kind]?.count ?? 0, lastSuccess: successes[kind],
                                failed: failures.contains(kind))
        }
    }

    private func refresh(settings: RadarDiscoveryPreferences) async throws -> [DiscoveryCandidate] {
        let enabled = WallstreetRankingKind.allCases.filter {
            $0 == .wikifolio ? settings.wikifolio : settings.performance
        }
        let loaded = await withTaskGroup(of: (WallstreetRankingKind, [WallstreetRankingEntry]?).self) { group in
            for kind in enabled {
                group.addTask { [page] in (kind, try? await page.load(kind)) }
            }
            var result: [(WallstreetRankingKind, [WallstreetRankingEntry]?)] = []
            for await row in group { result.append(row) }
            return result
        }
        try Task.checkCancellation()
        failures.removeAll()
        for (kind, rows) in loaded {
            if let rows {
                entries[kind] = rows
                successes[kind] = Date()
            } else { failures.insert(kind) }
            AppDiagnostics.shared.record(rows == nil ? .warning : .info, "Discovery", "ranking-refresh",
                                         "source=\(kind.rawValue) received=\(rows?.count ?? 0) cached=\(entries[kind]?.count ?? 0)")
        }
        let combined = Self.merge(
            wikifolio: settings.wikifolio ? entries[.wikifolio] ?? [] : [],
            performance: settings.performance ? entries[.performance] ?? [] : [],
            settings: settings, observedAt: successes
        )
        guard !combined.isEmpty else { throw DiscoveryDataError.invalidCandidate }
        candidates = combined
        preferences = settings
        nextRefresh = Date().addingTimeInterval(failures.isEmpty ? 1_800 : 300)
        return combined
    }

    static func merge(wikifolio: [WallstreetRankingEntry], performance: [WallstreetRankingEntry],
                      settings: RadarDiscoveryPreferences,
                      observedAt: [WallstreetRankingKind: Date]) -> [DiscoveryCandidate] {
        let activity = Dictionary(wikifolio.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })
        let movers = Dictionary(performance.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })
        return Set(activity.keys).union(movers.keys).compactMap { path -> DiscoveryCandidate? in
            guard let entry = activity[path] ?? movers[path] else { return nil }
            let evidence = DiscoveryRankingEvidence(wikifolioRank: activity[path]?.rank,
                performanceRank: movers[path]?.rank, wikifolioTrades: activity[path]?.trades)
            let dates = [activity[path] == nil ? nil : observedAt[.wikifolio],
                         movers[path] == nil ? nil : observedAt[.performance]].compactMap { $0 }
            let observed = Int64((dates.min() ?? .distantPast).timeIntervalSince1970 * 1_000)
            return DiscoveryCandidate(sourceID: "wallstreet_rankings", instrumentID: path,
                category: movers[path] == nil ? .mostTraded : .top, rank: entry.rank,
                observedAtMillis: observed, resolved: nil,
                origin: movers[path] == nil ? nil : DiscoveryRankingOrigin(page: .allIndices, period: .day),
                displayName: entry.name, marketMetrics: movers[path]?.metrics,
                rankingEvidence: evidence, discoveryPriority: evidence.priority(settings: settings))
        }.sorted {
            let left = $0.discoveryPriority ?? 0, right = $1.discoveryPriority ?? 0
            return left == right ? $0.instrumentID < $1.instrumentID : left > right
        }
    }
}
