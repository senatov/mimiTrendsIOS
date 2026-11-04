import XCTest
import SwiftUI
@testable import MiMiTrends

final class RadarPaneLayoutTests: XCTestCase {
    func testSourceDrawerLeavesSignalSpaceOnIPad() {
        XCTAssertEqual(RadarPaneLayout.sourceDrawerWidth(totalWidth: 834), 340)
        XCTAssertEqual(RadarPaneLayout.signalWidth(totalWidth: 834, sourcesOpen: false), 834)
        XCTAssertEqual(RadarPaneLayout.signalWidth(totalWidth: 834, sourcesOpen: true), 488)
        XCTAssertGreaterThan(RadarPaneLayout.signalWidth(totalWidth: 1_194, sourcesOpen: true), 700)
    }

    func testNarrowWindowUsesSourceSheetInsteadOfInlineDrawer() {
        XCTAssertLessThan(600, RadarPaneLayout.minimumInlineSourceWidth)
        XCTAssertGreaterThanOrEqual(834, RadarPaneLayout.minimumInlineSourceWidth)
    }

    func testWidePanelsAndChartFitShortIPadWorkspace() {
        let totalHeight: CGFloat = 350
        let panels = RadarPaneLayout.wideTopHeight(totalHeight: totalHeight, ratio: 0.62)

        XCTAssertGreaterThanOrEqual(panels, 180)
        XCTAssertGreaterThanOrEqual(totalHeight - RadarPaneLayout.handleSize - panels, 100)
    }

    func testDraggedAndRestoredHeightRatiosAreClamped() {
        XCTAssertEqual(RadarPaneLayout.wideTopHeight(totalHeight: 500, ratio: -1), 180)
        XCTAssertEqual(RadarPaneLayout.wideTopHeight(totalHeight: 500, ratio: 2), 386)
        XCTAssertEqual(RadarPaneLayout.wideTopHeight(totalHeight: 500, ratio: .nan), 301.32, accuracy: 0.01)
    }
}
