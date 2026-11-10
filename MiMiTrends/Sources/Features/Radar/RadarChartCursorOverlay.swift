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
            if readsPrice, let y = proxy.position(forY: selectedPrice) {
                cursorTag(selectedPrice.formatted(.currency(code: displayCurrency).precision(.fractionLength(2))))
                    .position(
                        x: geometry.size.width - 28,
                        y: min(max(plotFrame.minY + y, 14), plotFrame.maxY - 14)
                    )
                    .accessibilityHidden(true)
            } else if !readsPrice, let x = proxy.position(forX: timeline.position(selectedBar.minuteEpochSeconds)) {
                cursorTag(selectedBar.chartDate.formatted(
                    .dateTime.day(.twoDigits).month(.twoDigits).year().hour().minute()
                ))
                .position(
                    x: min(max(plotFrame.minX + x, 72), geometry.size.width - 72),
                    y: geometry.size.height - 12
                )
                .accessibilityHidden(true)
            }
        }
    }

    private func cursorTag(_ value: String) -> some View {
        Text(value)
            .font(.caption2.monospacedDigit())
            .foregroundStyle(TrendsColors.ink)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Color.yellow.opacity(0.2), in: RoundedRectangle(cornerRadius: 3))
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.blue.opacity(0.7), lineWidth: 1))
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
