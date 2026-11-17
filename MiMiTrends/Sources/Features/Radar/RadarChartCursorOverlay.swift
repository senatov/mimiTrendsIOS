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
               let x = proxy.position(forX: timeline.position(selectedBar.minuteEpochSeconds)),
               let y = proxy.position(forY: selectedPrice) {
                let point = CGPoint(x: plotFrame.minX + x, y: plotFrame.minY + y)
                cursorBubble(date: selectedBar.chartDate, price: selectedPrice)
                    .position(
                        x: min(max(point.x, plotFrame.minX + 85), plotFrame.maxX - 85),
                        y: point.y - 38 >= plotFrame.minY + 24 ? point.y - 38 : point.y + 38
                    )
                    .accessibilityHidden(true)
            }
        }
    }

    private func cursorBubble(date: Date, price: Double) -> some View {
        VStack(spacing: 1) {
            Text(date.formatted(.dateTime.day(.twoDigits).month(.twoDigits).year().hour().minute()))
            Text(price.formatted(.currency(code: displayCurrency).precision(.fractionLength(2))))
                .fontWeight(.semibold)
        }
            .font(.caption.monospacedDigit())
            .foregroundStyle(TrendsColors.ink)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.blue.opacity(0.7), lineWidth: 1))
            .fixedSize()
            .allowsHitTesting(false)
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
