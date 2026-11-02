import XCTest
@testable import MiMiTrends

final class RadarPaneLayoutTests: XCTestCase {
    func testWidePanelsStayReadableAtDefaultWindowSize() {
        let width = RadarPaneLayout.wideColumnWidth(totalWidth: 1024, ratio: 0.72)
        let height = RadarPaneLayout.wideTopHeight(totalHeight: 650, ratio: 0.62)

        XCTAssertGreaterThanOrEqual(width, 320)
        XCTAssertGreaterThanOrEqual(1024 - RadarPaneLayout.handleSize - width, 240)
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
        XCTAssertEqual(RadarPaneLayout.wideColumnWidth(totalWidth: 900, ratio: -1), 320)
        XCTAssertEqual(RadarPaneLayout.wideColumnWidth(totalWidth: 900, ratio: 2), 646)
        XCTAssertEqual(RadarPaneLayout.wideTopHeight(totalHeight: 500, ratio: .nan), 301.32, accuracy: 0.01)
    }

    func testStackedPanelsReserveChartAndSourceSpace() {
        let totalHeight: CGFloat = 600
        let signals = RadarPaneLayout.stackedSignalHeight(totalHeight: totalHeight, ratio: 1)
        let sources = RadarPaneLayout.stackedSourceHeight(
            totalHeight: totalHeight, signalHeight: signals, ratio: 1
        )

        XCTAssertGreaterThanOrEqual(signals, 140)
        XCTAssertGreaterThanOrEqual(sources, 120)
        XCTAssertGreaterThanOrEqual(
            totalHeight - 2 * RadarPaneLayout.handleSize - signals - sources, 260
        )
    }
}
