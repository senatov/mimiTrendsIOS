import Charts
import SwiftUI

struct LSQuoteCursorOverlay: View {
    let proxy: ChartProxy
    let observations: [LSQuoteObservation]
    let selectedQuote: LSQuoteObservation?
    let selectedPrice: Double?
    let onSelection: (LSQuoteObservation, Double) -> Void
    let isPinned: Bool
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
                        case .active(let location): if !isPinned { select(at: location, in: geometry) }
                        case .ended: if !isPinned { onExit() }
                        }
                    }
                    .onTapGesture {
                        hasChartFocus = true
                        onTogglePin()
                    }
                    .focusable()
                    .focused($hasChartFocus)
                    #else
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { select(at: $0.location, in: geometry) }
                        .onEnded { _ in onTogglePin() })
                    #endif
                cursorTags(in: geometry)
            }
            .onKeyPress(.escape) {
                guard isPinned else { return .ignored }
                onExit()
                return .handled
            }
        }
    }

    @ViewBuilder
    private func cursorTags(in geometry: GeometryProxy) -> some View {
        if let quote = selectedQuote, let price = selectedPrice, let anchor = proxy.plotFrame {
            let plot = geometry[anchor]
            if let y = proxy.position(forY: price) {
                cursorTag(price.formatted(.currency(code: "EUR").precision(.fractionLength(2))))
                    .position(x: geometry.size.width - 34, y: min(max(plot.minY + y, 16), plot.maxY - 16))
            }
            if let x = proxy.position(forX: Date(timeIntervalSince1970: Double(quote.observedAtMillis) / 1_000)) {
                cursorTag(Date(timeIntervalSince1970: Double(quote.observedAtMillis) / 1_000)
                    .formatted(.dateTime.day(.twoDigits).month(.twoDigits).hour().minute().second()))
                    .position(x: min(max(plot.minX + x, 68), geometry.size.width - 68), y: geometry.size.height - 13)
            }
        }
    }

    private func cursorTag(_ value: String) -> some View {
        Text(value)
            .font(.caption2.monospacedDigit())
            .foregroundStyle(TrendsColors.ink)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.yellow.opacity(0.2), in: RoundedRectangle(cornerRadius: 3))
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.blue.opacity(0.7), lineWidth: 1))
            .fixedSize()
            .allowsHitTesting(false)
    }

    private func select(at location: CGPoint, in geometry: GeometryProxy) {
        guard let anchor = proxy.plotFrame else { return }
        let plot = geometry[anchor]
        guard plot.contains(location),
              let x = proxy.value(atX: location.x - plot.minX, as: Date.self),
              let nearest = observations.min(by: {
                  abs($0.observedAtMillis - Int64(x.timeIntervalSince1970 * 1_000)) <
                      abs($1.observedAtMillis - Int64(x.timeIntervalSince1970 * 1_000))
              }) else { return }
        let plotPointY = location.y - plot.minY
        let price = proxy.value(atY: plotPointY, as: Double.self) ?? nearest.midpoint
        onSelection(nearest, price)
    }
}
