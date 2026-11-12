import SwiftUI

struct RadarWorkspace<Signals: View, Sources: View, Plot: View>: View {
    let signals: (Bool, CGFloat) -> Signals
    let sources: () -> Sources
    let plot: () -> Plot
    @Binding var showingSources: Bool

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("radar.wideTopRatio.v2") private var savedTopRatio = 0.62
    @State private var topDrag: Double?
    @State private var topStart: Double?

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { geometry in
                if geometry.size.height >= RadarPaneLayout.minimumWideHeight &&
                    !dynamicTypeSize.isAccessibilitySize {
                    splitWorkspace(size: geometry.size)
                } else {
                    ScrollView {
                        VStack(spacing: 8) {
                            radarAndSources(width: geometry.size.width)
                                .frame(height: max(220, geometry.size.height * 0.55))
                            plot().frame(height: 420)
                        }
                    }
                }
            }
        }
    }

    private func splitWorkspace(size: CGSize) -> some View {
        let topHeight = RadarPaneLayout.wideTopHeight(
            totalHeight: size.height, ratio: topDrag ?? savedTopRatio
        )
        let availableHeight = size.height - RadarPaneLayout.handleSize
        return VStack(spacing: 0) {
            radarAndSources(width: size.width)
                .frame(height: topHeight)
            chartSplitHandle(topHeight: topHeight, availableHeight: availableHeight)
            plot().frame(height: max(100, availableHeight - topHeight))
        }
    }

    private func radarAndSources(width: CGFloat) -> some View {
        let inlineDrawer = width >= RadarPaneLayout.minimumInlineSourceWidth && !dynamicTypeSize.isAccessibilitySize
        let drawerWidth = RadarPaneLayout.sourceDrawerWidth(totalWidth: width)
        let signalWidth = RadarPaneLayout.signalWidth(totalWidth: width, sourcesOpen: showingSources && inlineDrawer)
        return HStack(alignment: .top, spacing: 6) {
            signals(signalWidth < 620 || dynamicTypeSize.isAccessibilitySize, signalWidth)
                .frame(width: signalWidth, alignment: .leading)
                .frame(maxHeight: .infinity)
            if showingSources && inlineDrawer {
                ScrollView(.vertical) {
                    sources().fixedSize(horizontal: false, vertical: true)
                }
                .frame(width: drawerWidth)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .frame(width: width, alignment: .leading)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: showingSources)
        .sheet(isPresented: Binding(
            get: { showingSources && !inlineDrawer },
            set: { showingSources = $0 }
        )) {
            NavigationStack {
                ScrollView { sources().padding(12) }
                    .frame(minWidth: 280, minHeight: 300)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            TrendsActionButton(title: "Done", systemImage: "checkmark") {
                                showingSources = false
                            }
                        }
                    }
            }
        }
    }

    private func chartSplitHandle(topHeight: CGFloat, availableHeight: CGFloat) -> some View {
        RadarSplitHandle(
            axis: .rows, value: Double(topHeight / availableHeight),
            onDrag: { delta in
                if topStart == nil { topStart = savedTopRatio }
                topDrag = Double(RadarPaneLayout.wideTopHeight(
                    totalHeight: availableHeight + RadarPaneLayout.handleSize,
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
                    totalHeight: availableHeight + RadarPaneLayout.handleSize,
                    ratio: savedTopRatio + Double(direction) * 0.05
                ) / availableHeight)
            }
        )
    }
}
