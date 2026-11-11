import Foundation

enum RadarScanPool {
    static let maximumSymbols = 200

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
