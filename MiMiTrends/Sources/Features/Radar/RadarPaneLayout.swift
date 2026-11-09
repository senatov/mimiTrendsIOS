import Foundation

enum RadarPaneLayout {
    static let handleSize: CGFloat = 14
    static let minimumWideHeight: CGFloat = 300
    static let maximumSourceDrawerWidth: CGFloat = 510
    static let minimumInlineSourceWidth: CGFloat = 650
    static let paneSpacing: CGFloat = 6

    static func sourceDrawerWidth(totalWidth: CGFloat) -> CGFloat {
        min(maximumSourceDrawerWidth, totalWidth * 0.63)
    }

    static func signalWidth(totalWidth: CGFloat, sourcesOpen: Bool) -> CGFloat {
        max(0, totalWidth -
            (sourcesOpen ? sourceDrawerWidth(totalWidth: totalWidth) + paneSpacing : 0))
    }

    static func wideTopHeight(totalHeight: CGFloat, ratio: Double) -> CGFloat {
        let available = max(0, totalHeight - handleSize)
        return clamp(available * safeRatio(ratio, fallback: 0.62),
                     minimum: 180, maximum: available - 100)
    }

    static func safeRatio(_ value: Double, fallback: Double) -> CGFloat {
        CGFloat(value.isFinite ? min(max(value, 0), 1) : fallback)
    }

    static func clamp(_ value: CGFloat, minimum: CGFloat, maximum: CGFloat) -> CGFloat {
        min(max(value, minimum), max(minimum, maximum))
    }
}
