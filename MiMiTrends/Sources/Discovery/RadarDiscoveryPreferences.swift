import Foundation

enum DiscoveryPriorityMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case balanced, activity, performance
    var id: String { rawValue }
    var title: String {
        switch self {
        case .balanced: "Balanced"
        case .activity: "Wikifolio activity first"
        case .performance: "Price movers first"
        }
    }
    var activityWeight: Double {
        switch self {
        case .balanced: 0.5
        case .activity: 0.7
        case .performance: 0.3
        }
    }
}

struct RadarDiscoveryPreferences: Equatable, Sendable {
    static let wikifolioKey = "discovery.wikifolio.enabled.v1"
    static let performanceKey = "discovery.performance.enabled.v1"
    static let priorityKey = "discovery.priority.v1"
    var endpointSignature = ""
    var wikifolio = true
    var performance = true
    var priority = DiscoveryPriorityMode.balanced

    static func load(defaults: UserDefaults = .standard) -> Self {
        var value = Self()
        value.endpointSignature = ProviderEndpointStore.url(for: .wallstreetWikifolio).absoluteString + "|" + ProviderEndpointStore.url(for: .wallstreetPerformance).absoluteString
        value.wikifolio = defaults.object(forKey: wikifolioKey) as? Bool ?? true
        value.performance = defaults.object(forKey: performanceKey) as? Bool ?? true
        if !value.wikifolio && !value.performance { value.wikifolio = true; value.performance = true }
        value.priority = DiscoveryPriorityMode(rawValue: defaults.string(forKey: priorityKey) ?? "") ?? .balanced
        return value
    }
}

struct DiscoveryRankingEvidence: Codable, Equatable, Sendable {
    let wikifolioRank: Int?
    let performanceRank: Int?
    let wikifolioTrades: Int?

    func priority(settings: RadarDiscoveryPreferences) -> Double {
        let activityWeight = settings.wikifolio ? settings.priority.activityWeight : 0
        let performanceWeight = settings.performance ? 1 - settings.priority.activityWeight : 0
        func value(_ rank: Int?) -> Double { rank.map { 1 / sqrt(Double(max(1, $0))) } ?? 0 }
        return 100 * (value(wikifolioRank) * activityWeight + value(performanceRank) * performanceWeight)
            / max(0.01, activityWeight + performanceWeight)
    }
}
