import Foundation

enum RadarPaneLayout {
    static let handleSize: CGFloat = 14
    static let minimumWideHeight: CGFloat = 300
    static let minimumStackedHeight: CGFloat = 548
    static let minimumSignalPaneWidth: CGFloat = 220
    static let minimumRightPaneWidth: CGFloat = 620
    static let paneSpacing: CGFloat = 8
    static let minimumWideWidth = minimumSignalPaneWidth + minimumRightPaneWidth + paneSpacing

    static func wideColumnWidth(totalWidth: CGFloat, ratio: Double) -> CGFloat {
        let available = max(0, totalWidth - paneSpacing)
        return clamp(available * safeRatio(ratio, fallback: 0.68),
                     minimum: minimumSignalPaneWidth, maximum: available - minimumRightPaneWidth)
    }

    static func wideTopHeight(totalHeight: CGFloat, ratio: Double) -> CGFloat {
        let available = max(0, totalHeight - handleSize)
        return clamp(available * safeRatio(ratio, fallback: 0.62),
                     minimum: 180, maximum: available - 100)
    }

    static func stackedSignalHeight(totalHeight: CGFloat, ratio: Double) -> CGFloat {
        let available = max(0, totalHeight - 2 * handleSize)
        return clamp(available * safeRatio(ratio, fallback: 0.48),
                     minimum: 140, maximum: available - 120 - 260)
    }

    static func stackedSourceHeight(
        totalHeight: CGFloat, signalHeight: CGFloat, ratio: Double
    ) -> CGFloat {
        let available = max(0, totalHeight - 2 * handleSize)
        return clamp(available * safeRatio(ratio, fallback: 0.25),
                     minimum: 120, maximum: available - signalHeight - 260)
    }

    static func safeRatio(_ value: Double, fallback: Double) -> CGFloat {
        CGFloat(value.isFinite ? min(max(value, 0), 1) : fallback)
    }

    static func clamp(_ value: CGFloat, minimum: CGFloat, maximum: CGFloat) -> CGFloat {
        min(max(value, minimum), max(minimum, maximum))
    }
}
