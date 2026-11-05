import Charts
import SwiftUI

struct RadarTradeAnchorPreference: PreferenceKey {
    static var defaultValue: [String: CGPoint] { [:] }
    static func reduce(value: inout [String: CGPoint], nextValue: () -> [String: CGPoint]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

struct RadarTradeAnchorReader: View {
    let proxy: ChartProxy
    let timeline: RadarChartTimeline
    let trades: [BrokerTradePosition]

    var body: some View {
        GeometryReader { geometry in
            Color.clear.preference(key: RadarTradeAnchorPreference.self, value: anchors(in: geometry))
        }
        .allowsHitTesting(false)
    }

    private func anchors(in geometry: GeometryProxy) -> [String: CGPoint] {
        guard let frame = proxy.plotFrame else { return [:] }
        let origin = geometry[frame].origin
        return Dictionary(trades.compactMap { trade in
            let first = timeline.bars.first?.minuteEpochSeconds ?? 0
            let isEntryVisible = trade.entryEpochSeconds >= first
            let epoch = isEntryVisible ? trade.entryEpochSeconds : trade.exitEpochSeconds ?? trade.entryEpochSeconds
            let price = isEntryVisible ? trade.entryPrice : trade.exitPrice ?? trade.entryPrice
            guard let x = proxy.position(forX: timeline.position(epoch)),
                  let y = proxy.position(forY: price) else { return nil }
            return (trade.id, CGPoint(x: origin.x + x, y: origin.y + y))
        }, uniquingKeysWith: { first, _ in first })
    }
}

/// Trade details occupy their own rail above the candles; only connectors enter the plot.
struct RadarTradeCardOverlay: View {
    let anchors: [String: CGPoint]
    let trades: [BrokerTradePosition]
    let currency: String
    @State private var offsets: [String: CGSize] = [:]
    @State private var dragStarts: [String: CGSize] = [:]

    private static let rowHeight: CGFloat = 84
    private static func columns(width: CGFloat) -> Int { max(1, Int(width / 240)) }
    static func railHeight(count: Int, width: CGFloat) -> CGFloat {
        guard count > 0 else { return 0 }
        return CGFloat((count + columns(width: width) - 1) / columns(width: width)) * rowHeight + 12
    }

    var body: some View {
        GeometryReader { geometry in
            let count = Self.columns(width: geometry.size.width)
            let width = geometry.size.width / CGFloat(count)
            let cardWidth = min(230, max(120, geometry.size.width - 12))
            let height = Self.railHeight(count: trades.count, width: geometry.size.width)
            ForEach(Array(trades.enumerated()), id: \.element.id) { index, trade in
                let base = CGPoint(x: (CGFloat(index % count) + 0.5) * width,
                                   y: CGFloat(index / count) * Self.rowHeight + Self.rowHeight / 2)
                let offset = offsets[trade.id] ?? .zero
                let center = CGPoint(x: min(max(base.x + offset.width, cardWidth / 2), geometry.size.width - cardWidth / 2),
                                     y: min(max(base.y + offset.height, 38), max(38, height - 44)))
                if let anchor = anchors[trade.id] {
                    let target = CGPoint(x: anchor.x, y: anchor.y + height)
                    Path { path in
                        let start = CGPoint(x: center.x, y: center.y + 34)
                        path.move(to: start)
                        path.addCurve(to: target,
                                      control1: CGPoint(x: start.x, y: start.y + 32),
                                      control2: CGPoint(x: target.x - 24, y: target.y - 36))
                    }
                    .stroke(.orange.opacity(0.8), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    .allowsHitTesting(false)
                }
                RadarChartTradeCard(trade: trade, chartCurrency: currency)
                    .frame(width: cardWidth, height: 72)
                    .contentShape(Rectangle())
                    .position(center)
                    .highPriorityGesture(DragGesture(minimumDistance: 3)
                        .onChanged { value in
                            let start = dragStarts[trade.id] ?? offsets[trade.id] ?? .zero
                            dragStarts[trade.id] = start
                            offsets[trade.id] = CGSize(width: start.width + value.translation.width,
                                                       height: start.height + value.translation.height)
                        }
                        .onEnded { value in
                            let start = dragStarts[trade.id] ?? .zero
                            let x = min(max(base.x + start.width + value.translation.width, cardWidth / 2),
                                        geometry.size.width - cardWidth / 2)
                            let y = min(max(base.y + start.height + value.translation.height, 38), max(38, height - 44))
                            offsets[trade.id] = CGSize(width: x - base.x, height: y - base.y)
                            dragStarts[trade.id] = nil
                        })
                    .accessibilityLabel("Trade details for \(trade.symbol)")
                    .accessibilityHint("Drag to reposition above the price chart")
                    .accessibilityAction(named: "Reset position") { offsets[trade.id] = nil }
                    .contextMenu { Button("Reset position") { offsets[trade.id] = nil } }
            }
        }
    }
}
