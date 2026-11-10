import Charts
import SwiftUI

/// Local highlights add depth while preserving the exact OHLC rectangle and volume height.
enum RadarCandleVisualStyle {
    static let rise = Color(red: 0.02, green: 0.53, blue: 0.37)
    static let fall = Color(red: 0.77, green: 0.12, blue: 0.20)
    static let fastLine = Color(red: 0.03, green: 0.38, blue: 0.78)
    static let slowLine = Color(red: 0.85, green: 0.38, blue: 0.06)

    static func body(rising: Bool) -> LinearGradient {
        let dark = rising ? Color(red: 0.01, green: 0.32, blue: 0.24) : Color(red: 0.48, green: 0.05, blue: 0.12)
        let light = rising ? Color(red: 0.50, green: 0.94, blue: 0.75) : Color(red: 1, green: 0.62, blue: 0.66)
        let base = rising ? rise : fall
        return LinearGradient(stops: [
            .init(color: dark, location: 0), .init(color: light, location: 0.18),
            .init(color: base, location: 0.48), .init(color: base, location: 0.76),
            .init(color: dark, location: 1)
        ], startPoint: .leading, endPoint: .trailing)
    }
}

struct RadarChartLastPriceLabel: View {
    let proxy: ChartProxy
    let price: Double
    let currency: String

    var body: some View {
        GeometryReader { geometry in
            if let anchor = proxy.plotFrame, let y = proxy.position(forY: price) {
                let frame = geometry[anchor]
                Text("Last " + price.formatted(.currency(code: currency).precision(.fractionLength(2))))
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .padding(.horizontal, 5).padding(.vertical, 3)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 4))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(.teal.opacity(0.5), lineWidth: 0.5))
                    .fixedSize()
                    .position(x: frame.maxX - 54,
                              y: min(max(frame.minY + y, frame.minY + 12), frame.maxY - 12))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
