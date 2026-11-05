import Foundation

enum DiscoveryCandidateSelector {
    static let maximumInputRows = 2_000
    static let maximumCandidates = maximumInputRows

    static func select(_ input: [DiscoveryCandidate], sourceID: String) throws -> [DiscoveryCandidate] {
        guard input.count <= maximumInputRows,
              !sourceID.isEmpty,
              input.allSatisfy({ $0.sourceID == sourceID }) else {
            throw DiscoveryDataError.invalidCandidate
        }
        for candidate in input { try candidate.validate() }

        if input.contains(where: { $0.discoveryPriority != nil }) {
            var seen = Set<String>()
            return input.sorted {
                let left = $0.discoveryPriority ?? 0, right = $1.discoveryPriority ?? 0
                return left == right ? $0.instrumentID < $1.instrumentID : left > right
            }.filter { seen.insert($0.identity).inserted }
        }
        let groups = DiscoveryCategory.selectionOrder.map { category in
            input.filter { $0.category == category }
                .sorted { sortKey($0) < sortKey($1) }
        }
        var selected: [DiscoveryCandidate] = []
        var seen = Set<String>()
        var rank = 0
        while groups.contains(where: { rank < $0.count }) {
            for group in groups where rank < group.count {
                let candidate = group[rank]
                if seen.insert(candidate.identity).inserted {
                    selected.append(candidate)
                }
            }
            rank += 1
        }
        return selected
    }

    private static func sortKey(_ candidate: DiscoveryCandidate) -> (Int, Int, Int, String) {
        let period = candidate.origin.flatMap { DiscoveryRankingPeriod.allCases.firstIndex(of: $0.period) } ?? 0
        let page = candidate.origin.flatMap { DiscoveryRankingPage.allCases.firstIndex(of: $0.page) } ?? 0
        return (candidate.rank, period, page, candidate.instrumentID)
    }
}
