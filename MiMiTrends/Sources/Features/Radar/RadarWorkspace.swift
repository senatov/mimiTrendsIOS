import SwiftUI

struct RadarWorkspace<Signals: View, Sources: View, Plot: View, Controls: View>: View {
    let signals: (Bool) -> Signals
    let sources: () -> Sources
    let plot: () -> Plot
    let controls: () -> Controls

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage("radar.wideTopRatio.v2") private var savedTopRatio = 0.62
    @State private var topDrag: Double?
    @State private var topStart: Double?

    private let sourcePanelHeight: CGFloat = 238

    var body: some View {
        GeometryReader { geometry in
            if dynamicTypeSize.isAccessibilitySize {
                scrollingFallback
            } else if geometry.size.width >= RadarPaneLayout.minimumWideWidth &&
                        geometry.size.height >= RadarPaneLayout.minimumWideHeight {
                wideWorkspace(size: geometry.size)
            } else if geometry.size.height >= RadarPaneLayout.minimumStackedHeight {
                stackedWorkspace(size: geometry.size)
            } else {
                scrollingFallback
            }
        }
    }

    private func wideWorkspace(size: CGSize) -> some View {
        let topHeight = RadarPaneLayout.wideTopHeight(
            totalHeight: size.height, ratio: topDrag ?? savedTopRatio
        )
        let leftWidth = RadarPaneLayout.wideColumnWidth(totalWidth: size.width, ratio: 0.68)
        let rightWidth = max(
            RadarPaneLayout.minimumRightPaneWidth,
            size.width - leftWidth - RadarPaneLayout.paneSpacing
        )
        let availableHeight = size.height - RadarPaneLayout.handleSize
        return VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                signals(leftWidth < 620)
                    .frame(width: leftWidth, height: topHeight)
                    .clipped()
                VStack(spacing: 6) {
                    sources()
                        .frame(height: sourcePanelHeight, alignment: .top)
                    controls()
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                .frame(width: rightWidth, height: topHeight, alignment: .top)
                .clipped()
                .layoutPriority(1)
            }
            .frame(width: size.width, alignment: .leading)
            .clipped()
            chartSplitHandle(topHeight: topHeight, availableHeight: availableHeight, totalHeight: size.height)
            plot().frame(height: max(100, availableHeight - topHeight))
        }
    }

    private func stackedWorkspace(size: CGSize) -> some View {
        let sourceHeight = min(sourcePanelHeight, max(190, size.height * 0.32))
        let controlsHeight = min(130, max(96, size.height * 0.18))
        let chartAndSignalHeight = max(0, size.height - sourceHeight - controlsHeight)
        let signalHeight = RadarPaneLayout.clamp(chartAndSignalHeight * 0.43, minimum: 140, maximum: chartAndSignalHeight - 150)
        return VStack(spacing: 6) {
            sources().frame(height: sourceHeight, alignment: .top)
            controls().frame(height: controlsHeight, alignment: .topLeading)
            signals(true).frame(height: signalHeight)
            plot().frame(maxHeight: .infinity)
        }
    }

    private func chartSplitHandle(topHeight: CGFloat, availableHeight: CGFloat, totalHeight: CGFloat) -> some View {
        RadarSplitHandle(
            axis: .rows, value: Double(topHeight / availableHeight),
            onDrag: { delta in
                if topStart == nil { topStart = savedTopRatio }
                topDrag = Double(RadarPaneLayout.wideTopHeight(
                    totalHeight: totalHeight,
                    ratio: (topStart ?? savedTopRatio) + Double(delta / availableHeight)
                ) / availableHeight)
            },
            onFinish: {
                if let topDrag { savedTopRatio = topDrag }
                topDrag = nil
                topStart = nil
            },
            onAdjust: { direction in
                savedTopRatio = Double(RadarPaneLayout.wideTopHeight(
                    totalHeight: totalHeight,
                    ratio: savedTopRatio + Double(direction) * 0.05
                ) / availableHeight)
            }
        )
    }

    private var scrollingFallback: some View {
        ScrollView {
            VStack(spacing: 10) {
                sources().frame(height: sourcePanelHeight, alignment: .top)
                controls()
                signals(true).frame(minHeight: 170)
                plot().frame(height: 420)
            }
        }
    }
}
