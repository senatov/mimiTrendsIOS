import Charts
import SwiftUI

struct RadarChartCursorOverlay: View {
    let proxy: ChartProxy
    let bars: [MinuteBar]
    let timeline: RadarChartTimeline
    let displayCurrency: String
    let readsPrice: Bool
    let selectedBar: MinuteBar?
    let selectedPrice: Double?
    let isPinned: Bool
    let onSelection: (MinuteBar, Double) -> Void
    let onTogglePin: () -> Void
    let onExit: () -> Void
    @FocusState private var hasChartFocus: Bool

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    #if os(macOS)
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            if !isPinned { select(at: location, in: geometry) }
                        case .ended:
                            if !isPinned { onExit() }
                        }
                    }
                    .onTapGesture {
                        hasChartFocus = true
                        onTogglePin()
                    }
                    .focusable()
                    .focused($hasChartFocus)
                    .onKeyPress(.escape) {
                        guard isPinned else { return .ignored }
                        onExit()
                        return .handled
                    }
                    #else
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { select(at: $0.location, in: geometry) }
                            .onEnded { _ in onTogglePin() }
                    )
                    #endif
                axisLabels(in: geometry)
            }
        }
    }

    @ViewBuilder
    private func axisLabels(in geometry: GeometryProxy) -> some View {
        if let selectedBar, let selectedPrice, let plotFrameAnchor = proxy.plotFrame {
            let plotFrame = geometry[plotFrameAnchor]
            ChartCursorLines(
                plot: plotFrame, x: proxy.position(forX: timeline.position(selectedBar.minuteEpochSeconds)),
                y: (readsPrice ? selectedPrice : nil).flatMap { proxy.position(forY: $0) }
            )
            if readsPrice,
               let x = proxy.position(forX: timeline.position(selectedBar.minuteEpochSeconds)) {
                let cardWidth = min(max(0, plotFrame.width - 16), 360)
                let cardX = x < plotFrame.width / 2
                    ? plotFrame.maxX - cardWidth - 8 : plotFrame.minX + 8
                cursorBubble(bar: selectedBar, price: selectedPrice)
                    .frame(width: cardWidth, alignment: .leading)
                    .offset(x: cardX, y: plotFrame.minY + 8)
            }
        }
    }

    private func cursorBubble(bar: MinuteBar, price: Double) -> some View {
        let change = (bar.close / bar.open - 1) * 100
        let range = (bar.high - bar.low) / bar.open * 100
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(bar.chartDate.formatted(.dateTime.day(.twoDigits).month(.twoDigits).year().hour().minute()))
                    .fontWeight(.semibold)
                Spacer(minLength: 4)
                Text(isPinned ? "PINNED" : "LIVE")
                    .foregroundStyle(.secondary)
            }
            Text(price.formatted(.currency(code: displayCurrency).precision(.fractionLength(2))))
                .font(.headline.monospacedDigit())
            Text("\(change > 0 ? "UP" : change < 0 ? "DOWN" : "FLAT") \(change > 0 ? "+" : "")\(change.formatted(.number.precision(.fractionLength(2))))% · Range \(range.formatted(.number.precision(.fractionLength(2))))%")
            Text("O \(formattedPrice(bar.open))  H \(formattedPrice(bar.high))  L \(formattedPrice(bar.low))  C \(formattedPrice(bar.close))")
            Text("Volume \(bar.volume >= 1_000 ? (bar.volume / 1_000).formatted(.number.precision(.fractionLength(1))) + "k" : bar.volume.formatted(.number.precision(.fractionLength(0))))")
        }
            .font(.caption.monospacedDigit())
            .foregroundStyle(TrendsColors.ink)
            .padding(12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.blue.opacity(0.35), lineWidth: 0.8))
            .allowsHitTesting(false)
            .accessibilityElement(children: .combine)
    }

    private func formattedPrice(_ price: Double) -> String {
        price.formatted(.currency(code: displayCurrency).precision(.fractionLength(2)))
    }

    private func select(at location: CGPoint, in geometry: GeometryProxy) {
        guard let plotFrameAnchor = proxy.plotFrame else { return }
        let plotFrame = geometry[plotFrameAnchor]
        guard plotFrame.contains(location) else { return }
        let plotPoint = CGPoint(
            x: location.x - plotFrame.minX,
            y: location.y - plotFrame.minY
        )
        guard let position = proxy.value(atX: plotPoint.x, as: Double.self),
              let bar = timeline.bar(at: position) else { return }
        let price = readsPrice
            ? proxy.value(atY: plotPoint.y, as: Double.self) ?? bar.close
            : bar.close
        onSelection(bar, price)
    }
}

extension MinuteBar {
    var chartDate: Date { Date(timeIntervalSince1970: TimeInterval(minuteEpochSeconds)) }
}

struct ChartCursorLines: View {
    let plot: CGRect
    let x: CGFloat?
    let y: CGFloat?

    var body: some View {
        Path { path in
            if let x, (0...plot.width).contains(x) {
                path.move(to: CGPoint(x: plot.minX + x, y: plot.minY))
                path.addLine(to: CGPoint(x: plot.minX + x, y: plot.maxY))
            }
            if let y, (0...plot.height).contains(y) {
                path.move(to: CGPoint(x: plot.minX, y: plot.minY + y))
                path.addLine(to: CGPoint(x: plot.maxX, y: plot.minY + y))
            }
        }
        .stroke(.primary.opacity(0.65), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
