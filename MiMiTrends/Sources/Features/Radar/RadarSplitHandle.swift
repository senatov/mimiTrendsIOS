import SwiftUI

enum RadarSplitAxis {
    case columns
    case rows
}

struct RadarSplitHandle: View {
    let axis: RadarSplitAxis
    let value: Double
    let onDrag: (CGFloat) -> Void
    let onFinish: () -> Void
    let onAdjust: (Int) -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Color.clear
            Capsule()
                .fill(Color.blue.opacity(colorScheme == .dark ? 0.75 : 0.42))
                .frame(
                    width: axis == .columns ? 3 : 48,
                    height: axis == .columns ? 48 : 3
                )
            Image(systemName: axis == .columns ? "arrow.left.and.right" : "arrow.up.and.down")
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(.blue)
                .padding(5)
                .background(
                    TrendsColors.surface,
                    in: RoundedRectangle(cornerRadius: 6)
                )
        }
        .frame(
            width: axis == .columns ? RadarPaneLayout.handleSize : nil,
            height: axis == .rows ? RadarPaneLayout.handleSize : nil
        )
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .global)
                .onChanged { movement in
                    onDrag(axis == .columns ? movement.translation.width : movement.translation.height)
                }
                .onEnded { _ in onFinish() }
        )
        .accessibilityElement()
        .accessibilityLabel(axis == .columns ? "Resize Radar and Sources" : "Resize panels and chart")
        .accessibilityValue("\(Int(value * 100)) percent")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onAdjust(1)
            case .decrement: onAdjust(-1)
            @unknown default: break
            }
        }
    }
}
