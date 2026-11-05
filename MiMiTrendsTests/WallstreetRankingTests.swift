import XCTest
@testable import MiMiTrends

final class WallstreetRankingTests: XCTestCase {
    func testWikifolioReadsTodayOnlyAndIgnoresNestedTooltipTables() throws {
        let header = "<thead><tr><th>Rang</th><th>Wertpapier</th><th>Käufe/Verkäufe</th><th>Trades</th></tr></thead>"
        let today = """
        <table>\(header)<tbody><tr><td>1.</td><td><a href="/aktien/sap-aktie">SAP</a></td>
        <td data-bs-title="<table><tr><td>Käufe:</td><td>9</td></tr></table>">bar</td><td>123</td></tr>
        <tr><td>2.</td><td><a href="/aktien/bayer-aktie">Bayer</a></td><td>bar</td><td>98</td></tr></tbody></table>
        """
        let week = "<table>\(header)<tr><td>1.</td><td><a href=\"/aktien/weekly-only-aktie\">Weekly</a></td><td>bar</td><td>900</td></tr></table>"
        let entries = try WallstreetRankingPageSource.decode(today + week, kind: .wikifolio)
        XCTAssertEqual(entries.map(\.path), ["/aktien/sap-aktie", "/aktien/bayer-aktie"])
        XCTAssertEqual(entries.first?.trades, 123)
        XCTAssertNil(entries.first?.metrics)
    }

    func testPerformanceReadsSignedPriceMetricsByColumnHeader() throws {
        let html = """
        <table><thead><tr><th>Platz</th><th>Wertpapier</th><th>Kurs</th><th>Perf. %</th><th>1 Monat %</th><th>7 Tage %</th><th>1 Jahr %</th></tr></thead>
        <tr><td>1.</td><td><a href="/aktien/sap-aktie">SAP</a></td><td>218,60</td><td>-1,25%</td><td>+2,5%</td><td>+3,5%</td><td>-10,0%</td></tr></table>
        """
        let rows = try WallstreetRankingPageSource.decode(html, kind: .performance)
        XCTAssertEqual(rows.first?.metrics?.price, 218.6)
        XCTAssertEqual(rows.first?.metrics?.change1dPercent, -1.25)
        XCTAssertEqual(rows.first?.metrics?.change30dPercent, 2.5)
        XCTAssertThrowsError(try WallstreetRankingPageSource.decode("<html>Unavailable</html>", kind: .performance))
    }

    func testCombinedPriorityDeduplicatesAndKeepsBothSourcesEvidence() throws {
        let common = entry("sap", rank: 1, trades: 100)
        let activity = entry("bayer", rank: 2, trades: 50)
        let mover = entry("basf", rank: 2, trades: nil)
        let settings = RadarDiscoveryPreferences()
        let dates: [WallstreetRankingKind: Date] = [.wikifolio: Date(), .performance: Date()]
        let result = WallstreetDiscoverySource.merge(wikifolio: [common, activity],
            performance: [common, mover], settings: settings, observedAt: dates)
        XCTAssertEqual(result.count, 3)
        let first = try XCTUnwrap(result.first)
        XCTAssertEqual(first.instrumentID, common.path)
        XCTAssertEqual(first.discoveryPriority, 100)
        XCTAssertEqual(first.rankingEvidence?.wikifolioRank, 1)
        XCTAssertEqual(first.rankingEvidence?.performanceRank, 1)
        XCTAssertEqual(first.rankingEvidence?.wikifolioTrades, 100)
        let selected = try DiscoveryCandidateSelector.select(result.reversed(), sourceID: "wallstreet_rankings")
        XCTAssertEqual(selected.first?.instrumentID, common.path)
        XCTAssertNoThrow(try DiscoverySnapshot(sourceID: "wallstreet_rankings",
            refreshedAtMillis: Int64(Date().timeIntervalSince1970 * 1_000), candidates: result).validate())
        let decoded = try JSONDecoder().decode(DiscoveryCandidate.self, from: JSONEncoder().encode(first))
        XCTAssertEqual(decoded.rankingEvidence, first.rankingEvidence)
    }

    func testPriorityPreferenceChangesOrderWithoutChangingSignalConfidence() {
        let activity = DiscoveryRankingEvidence(wikifolioRank: 1, performanceRank: nil, wikifolioTrades: 100)
        let mover = DiscoveryRankingEvidence(wikifolioRank: nil, performanceRank: 1, wikifolioTrades: nil)
        var settings = RadarDiscoveryPreferences()
        settings.priority = .activity
        XCTAssertGreaterThan(activity.priority(settings: settings), mover.priority(settings: settings))
        settings.priority = .performance
        XCTAssertLessThan(activity.priority(settings: settings), mover.priority(settings: settings))
        settings.wikifolio = false
        XCTAssertEqual(mover.priority(settings: settings), 100, accuracy: 0.00001)
    }

    private func entry(_ name: String, rank: Int, trades: Int?) -> WallstreetRankingEntry {
        WallstreetRankingEntry(path: "/aktien/\(name)-aktie", name: name, rank: rank, trades: trades, metrics: nil)
    }
}
