import Foundation

enum RadarScanPool {
    static let maximumSymbols = 255
    static let maximumShortDrops = 24
    private static let maximumActiveUS = 96
    private static let maximumActiveGerman = 64
    private static let maximumStrongRisers = 24

    static func withRetainedSymbols(_ retained: [String], ranked: [String], watchlist: [String] = [], drops: [String] = []) -> [String] {
        var seen = Set<String>()
        let urgent = Array(drops.uniqued().prefix(maximumShortDrops))
        let preferred = Array(watchlist.prefix(16)).appendingUnique(urgent)
            .appendingUnique(Array(retained.uniqued().prefix(16)))
        return Array((preferred + watchlist + ranked)
            .filter { seen.insert($0).inserted }.prefix(maximumSymbols))
    }

    static func prioritizedSymbols(activeUS: [String], activeGerman: [String],
                                   strongUS: [String] = [], strongGerman: [String] = [],
                                   volatileUS: [String], volatileGerman: [String],
                                   germanOpen: Bool, usOpen: Bool) -> [String] {
        let strong = MarketRadarScanner.interleave(
            usOpen ? strongUS : [], germanOpen ? strongGerman : [],
            limit: maximumStrongRisers)
        let us = usOpen ? activeUS.filter(MarketCandidateFilter.supportsYahooBars) : []
        let german = germanOpen ? activeGerman.filter(MarketCandidateFilter.supportsYahooBars) : []
        let active = MarketRadarScanner.interleave(Array(us.prefix(maximumActiveUS)),
                                                    Array(german.prefix(maximumActiveGerman)),
                                                    limit: maximumSymbols)
        let volatility = MarketRadarScanner.interleave(
            usOpen ? volatileUS : [], germanOpen ? volatileGerman : [], limit: maximumSymbols)
        var seen = Set<String>()
        return (strong + active + volatility).filter {
            MarketCandidateFilter.supportsYahooBars(symbol: $0) && seen.insert($0).inserted
        }.prefix(maximumSymbols).map { $0 }
    }

    static func symbols(baseline: [String], yahoo: [String], secondary: [String], german: [String],
                        germanOpen: Bool, usOpen: Bool = true, excluded: Set<String> = []) -> [String] {
        func eligible(_ symbols: [String]) -> [String] {
            symbols.filter {
                !excluded.contains($0) && MarketCandidateFilter.supportsYahooBars(symbol: $0) &&
                    (MarketCandidateFilter.isGermanSymbol($0) ? germanOpen : usOpen)
            }
        }
        let extra = MarketRadarScanner.interleave(eligible(yahoo), eligible(secondary), limit: maximumSymbols)
        let mixed = MarketRadarScanner.interleave(extra, eligible(german), limit: maximumSymbols)
        return MarketRadarScanner.interleave(eligible(baseline), mixed, limit: maximumSymbols)
    }
}

private extension Array where Element == String {
    func uniqued() -> [String] {
        var seen = Set<String>()
        return filter { seen.insert($0).inserted }
    }
}
