import Foundation

enum DiscoveryCategory: String, Codable, CaseIterable, Sendable {
    case top, flop, mostTraded, trending, gapUp, gapDown, reversalUp, reversalDown, highRange

    static let selectionOrder: [Self] = [
        .flop, .mostTraded, .trending, .top, .gapDown, .gapUp,
        .reversalDown, .reversalUp, .highRange
    ]
}

struct ResolvedMarketSymbol: Codable, Equatable, Sendable {
    let symbol: String
    let exchangeMIC: String
    let currency: String

    func validate() throws {
        guard !symbol.isEmpty, symbol.utf8.count <= 32,
              !symbol.unicodeScalars.contains(where: CharacterSet.whitespacesAndNewlines.contains),
              exchangeMIC.range(of: "^[A-Z0-9]{4}$", options: .regularExpression) != nil,
              currency.range(of: "^[A-Z]{3}$", options: .regularExpression) != nil else {
            throw DiscoveryDataError.invalidCandidate
        }
    }
}

struct DiscoveryMarketMetrics: Codable, Equatable, Sendable {
    let price: Double
    let change1dPercent: Double
    let change7dPercent: Double
    let change30dPercent: Double
    let change1yPercent: Double

    func changePercent(for period: DiscoveryRankingPeriod?) -> Double {
        switch period {
        case .day, .activity, nil: change1dPercent
        case .week: change7dPercent
        case .month: change30dPercent
        case .year: change1yPercent
        }
    }

    func validate() throws {
        guard price.isFinite, price > 0,
              change1dPercent.isFinite, change7dPercent.isFinite,
              change30dPercent.isFinite, change1yPercent.isFinite else {
            throw DiscoveryDataError.invalidCandidate
        }
    }
}

struct DiscoveryCandidate: Codable, Equatable, Sendable {
    let sourceID: String
    let instrumentID: String
    let displayName: String?
    let category: DiscoveryCategory
    let rank: Int
    let observedAtMillis: Int64
    let resolved: ResolvedMarketSymbol?
    let origin: DiscoveryRankingOrigin?
    let marketMetrics: DiscoveryMarketMetrics?
    let rankingEvidence: DiscoveryRankingEvidence?
    let discoveryPriority: Double?

    init(sourceID: String, instrumentID: String, category: DiscoveryCategory,
         rank: Int, observedAtMillis: Int64, resolved: ResolvedMarketSymbol?,
         origin: DiscoveryRankingOrigin? = nil, displayName: String? = nil,
         marketMetrics: DiscoveryMarketMetrics? = nil, rankingEvidence: DiscoveryRankingEvidence? = nil,
         discoveryPriority: Double? = nil) {
        self.sourceID = sourceID
        self.instrumentID = instrumentID
        self.displayName = displayName
        self.category = category
        self.rank = rank
        self.observedAtMillis = observedAtMillis
        self.resolved = resolved
        self.origin = origin
        self.marketMetrics = marketMetrics
        self.rankingEvidence = rankingEvidence
        self.discoveryPriority = discoveryPriority
    }

    var identity: String { "\(sourceID):\(instrumentID)" }
    var isScanReady: Bool { resolved != nil }

    func validate() throws {
        guard sourceID.range(of: "^[A-Za-z0-9_-]{1,64}$", options: .regularExpression) != nil,
              !instrumentID.isEmpty, instrumentID.utf8.count <= 256,
              displayName.map({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.utf8.count <= 200 }) ?? true,
              rank > 0, rank <= 1_000,
              observedAtMillis > 0 else {
            throw DiscoveryDataError.invalidCandidate
        }
        if let evidence = rankingEvidence {
            guard [evidence.wikifolioRank, evidence.performanceRank].compactMap({ $0 })
                .allSatisfy({ (1...50).contains($0) }),
                  evidence.wikifolioTrades.map({ $0 >= 0 }) ?? true else {
                throw DiscoveryDataError.invalidCandidate
            }
        }
        if let discoveryPriority {
            guard discoveryPriority.isFinite, (0...100).contains(discoveryPriority) else {
                throw DiscoveryDataError.invalidCandidate
            }
        }
        try resolved?.validate()
        try marketMetrics?.validate()
        if let origin {
            guard origin.page.category == category, origin.period.isValid(for: origin.page),
                  rank <= DiscoveryRankingBatch.maximumRows else {
                throw DiscoveryDataError.invalidCandidate
            }
        }
    }
}

enum DiscoveryDataError: LocalizedError {
    case invalidCandidate
    case invalidSnapshot

    var errorDescription: String? {
        switch self {
        case .invalidCandidate: "The discovery source returned an invalid instrument."
        case .invalidSnapshot: "The saved discovery snapshot is invalid or uses a newer format."
        }
    }
}
