import SwiftUI

struct RadarWorkspace<Signals: View, Sources: View, Plot: View>: View {
    let signals: (Bool) -> Signals
    let sources: () -> Sources
    let plot: () -> Plot

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage("radar.wideColumnRatio.v1") private var savedColumnRatio = 0.72
    @AppStorage("radar.wideTopRatio.v2") private var savedTopRatio = 0.62
    @AppStorage("radar.stackedSignalRatio.v2") private var savedSignalRatio = 0.48
    @AppStorage("radar.stackedSourceRatio.v2") private var savedSourceRatio = 0.25
    @State private var columnDrag: Double?
    @State private var topDrag: Double?
    @State private var signalDrag: Double?
    @State private var sourceDrag: Double?
    @State private var columnStart: Double?
    @State private var topStart: Double?
    @State private var signalStart: Double?
    @State private var sourceStart: Double?

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
        let leftWidth = RadarPaneLayout.wideColumnWidth(
            totalWidth: size.width, ratio: columnDrag ?? savedColumnRatio
        )
        let topHeight = RadarPaneLayout.wideTopHeight(
            totalHeight: size.height, ratio: topDrag ?? savedTopRatio
        )
        let availableWidth = size.width - RadarPaneLayout.handleSize
        let availableHeight = size.height - RadarPaneLayout.handleSize
        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                signals(leftWidth < 620)
                    .frame(width: leftWidth, height: topHeight)
                RadarSplitHandle(
                    axis: .columns, value: Double(leftWidth / availableWidth),
                    onDrag: { delta in
                        if columnStart == nil { columnStart = savedColumnRatio }
                        columnDrag = Double(RadarPaneLayout.wideColumnWidth(
                            totalWidth: size.width,
                            ratio: (columnStart ?? savedColumnRatio) + Double(delta / availableWidth)
                        ) / availableWidth)
                    },
                    onFinish: {
                        if let columnDrag { savedColumnRatio = columnDrag }
                        columnDrag = nil
                        columnStart = nil
                    },
                    onAdjust: { direction in
                        savedColumnRatio = Double(RadarPaneLayout.wideColumnWidth(
                            totalWidth: size.width,
                            ratio: savedColumnRatio + Double(direction) * 0.05
                        ) / availableWidth)
                    }
                )
                sources()
                    .frame(width: availableWidth - leftWidth, height: topHeight)
            }
            RadarSplitHandle(
                axis: .rows, value: Double(topHeight / availableHeight),
                onDrag: { delta in
                    if topStart == nil { topStart = savedTopRatio }
                    topDrag = Double(RadarPaneLayout.wideTopHeight(
                        totalHeight: size.height,
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
                        totalHeight: size.height,
                        ratio: savedTopRatio + Double(direction) * 0.05
                    ) / availableHeight)
                }
            )
            plot()
                .frame(height: availableHeight - topHeight)
        }
    }

    private func stackedWorkspace(size: CGSize) -> some View {
        let availableHeight = size.height - 2 * RadarPaneLayout.handleSize
        let signalHeight = RadarPaneLayout.stackedSignalHeight(
            totalHeight: size.height, ratio: signalDrag ?? savedSignalRatio
        )
        let sourceHeight = RadarPaneLayout.stackedSourceHeight(
            totalHeight: size.height, signalHeight: signalHeight,
            ratio: sourceDrag ?? savedSourceRatio
        )
        return VStack(spacing: 0) {
            signals(true).frame(height: signalHeight)
            RadarSplitHandle(
                axis: .rows, value: Double(signalHeight / availableHeight),
                onDrag: { delta in
                    if signalStart == nil { signalStart = savedSignalRatio }
                    signalDrag = Double(RadarPaneLayout.stackedSignalHeight(
                        totalHeight: size.height,
                        ratio: (signalStart ?? savedSignalRatio) + Double(delta / availableHeight)
                    ) / availableHeight)
                },
                onFinish: {
                    if let signalDrag { savedSignalRatio = signalDrag }
                    signalDrag = nil
                    signalStart = nil
                },
                onAdjust: { direction in
                    savedSignalRatio = Double(RadarPaneLayout.stackedSignalHeight(
                        totalHeight: size.height,
                        ratio: savedSignalRatio + Double(direction) * 0.05
                    ) / availableHeight)
                }
            )
            sources().frame(height: sourceHeight)
            RadarSplitHandle(
                axis: .rows, value: Double(sourceHeight / availableHeight),
                onDrag: { delta in
                    if sourceStart == nil { sourceStart = savedSourceRatio }
                    sourceDrag = Double(RadarPaneLayout.stackedSourceHeight(
                        totalHeight: size.height, signalHeight: signalHeight,
                        ratio: (sourceStart ?? savedSourceRatio) + Double(delta / availableHeight)
                    ) / availableHeight)
                },
                onFinish: {
                    if let sourceDrag { savedSourceRatio = sourceDrag }
                    sourceDrag = nil
                    sourceStart = nil
                },
                onAdjust: { direction in
                    savedSourceRatio = Double(RadarPaneLayout.stackedSourceHeight(
                        totalHeight: size.height, signalHeight: signalHeight,
                        ratio: savedSourceRatio + Double(direction) * 0.05
                    ) / availableHeight)
                }
            )
            plot().frame(height: availableHeight - signalHeight - sourceHeight)
        }
    }

    private var scrollingFallback: some View {
        ScrollView {
            VStack(spacing: 10) {
                signals(true).frame(height: 170)
                sources().frame(height: 145)
                plot().frame(height: 420)
            }
        }
    }
}
