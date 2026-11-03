import XCTest
import SwiftUI
@testable import MiMiTrends

final class RadarPaneLayoutTests: XCTestCase {
    func testWidePanelsStayReadableAtDefaultWindowSize() {
        let width = RadarPaneLayout.wideColumnWidth(totalWidth: 1024, ratio: 0.72)
        let height = RadarPaneLayout.wideTopHeight(totalHeight: 650, ratio: 0.62)

        XCTAssertGreaterThanOrEqual(width, 220)
        XCTAssertGreaterThanOrEqual(
            1024 - RadarPaneLayout.paneSpacing - width,
            RadarPaneLayout.minimumRightPaneWidth
        )
        XCTAssertGreaterThanOrEqual(height, 180)
        XCTAssertGreaterThanOrEqual(650 - RadarPaneLayout.handleSize - height, 100)
    }

    func testWidePanelsAndChartFitShortIPadWorkspace() {
        let totalHeight: CGFloat = 350
        let panels = RadarPaneLayout.wideTopHeight(totalHeight: totalHeight, ratio: 0.62)

        XCTAssertGreaterThanOrEqual(panels, 180)
        XCTAssertGreaterThanOrEqual(totalHeight - RadarPaneLayout.handleSize - panels, 100)
    }

    func testDraggedAndRestoredRatiosAreClamped() {
        XCTAssertEqual(RadarPaneLayout.wideColumnWidth(totalWidth: 900, ratio: -1), 220)
        XCTAssertEqual(RadarPaneLayout.wideColumnWidth(totalWidth: 900, ratio: 2), 272)
        XCTAssertEqual(RadarPaneLayout.wideTopHeight(totalHeight: 500, ratio: .nan), 301.32, accuracy: 0.01)
    }

    func testRightPaneKeepsPriorityWhenWindowNarrows() {
        for totalWidth: CGFloat in [880, 920, 1_100, 1_600] {
            let leftWidth = RadarPaneLayout.wideColumnWidth(totalWidth: totalWidth, ratio: 0.9)
            let rightWidth = totalWidth - RadarPaneLayout.paneSpacing - leftWidth
            XCTAssertGreaterThanOrEqual(rightWidth, RadarPaneLayout.minimumRightPaneWidth)
        }
    }

    func testTelemetryColumnsUseTheirOwnContentWidths() {
        let sources = [RadarTelemetrySource(
            name: "wallstreetONLINE", status: "NO FRESH QUOTES",
            statusColor: .red, dotColor: .red,
            received: 1_234_567, valid: 12, requests: 2, errors: 0,
            canShowCandidates: true
        )]
        let narrow = RadarSourceTableLayout.fit(
            sources: sources, availableWidth: 320, fontName: "System", fontSize: 14
        )
        let wide = RadarSourceTableLayout.fit(
            sources: sources, availableWidth: 800, fontName: "System", fontSize: 14
        )

        XCTAssertGreaterThan(narrow.table, 320)
        XCTAssertGreaterThan(narrow.width(for: .received), narrow.width(for: .errors))
        XCTAssertGreaterThan(narrow.width(for: .source), narrow.width(for: .requests))
        XCTAssertEqual(wide.table, 800, accuracy: 0.01)
        XCTAssertGreaterThan(wide.width(for: .source), narrow.width(for: .source))
    }
}
