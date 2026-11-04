import SwiftUI

struct RadarSourceTab: View {
    let isOpen: Bool
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false
    @AppStorage("controls.tab.fontSize.v1") private var fontSize = ControlAppearance.tabFontSize
    @AppStorage("controls.tab.height.v1") private var tabHeight = ControlAppearance.tabHeight
    @AppStorage("controls.tab.bottomRadius.v1") private var bottomRadius = ControlAppearance.tabBottomRadius
    @AppStorage("controls.tab.openBackground.v1") private var openBackground = ControlAppearance.tabOpenBackground
    @AppStorage("controls.tab.closedBackground.v1") private var closedBackground = ControlAppearance.tabClosedBackground
    @AppStorage("controls.tab.openText.v1") private var openText = ControlAppearance.tabOpenText
    @AppStorage("controls.tab.closedText.v1") private var closedText = ControlAppearance.tabClosedText

    var body: some View {
        Button(action: action) {
            Label("Sources", systemImage: "sidebar.right")
                .font(.system(size: CGFloat(fontSize), weight: .regular))
                .foregroundStyle(textColor)
                .frame(width: 112, height: CGFloat(tabHeight))
                .background {
                    tabShape.fill(
                        LinearGradient(
                            colors: isOpen
                                ? [backgroundColor, backgroundColor.opacity(colorScheme == .dark ? 0.78 : 0.92)]
                                : [backgroundColor.opacity(colorScheme == .dark ? 0.30 : 0.64),
                                   backgroundColor.opacity(colorScheme == .dark ? 0.24 : 0.58)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                }
                .overlay {
                    tabShape.strokeBorder(
                        isOpen ? Color.blue.opacity(0.94) : Color.gray.opacity(isHovered ? 0.72 : 0.52),
                        lineWidth: isOpen ? 0.8 : 0.65
                    )
                }
                .shadow(color: .black.opacity(isOpen ? 0.18 : 0.10), radius: isOpen ? 1.8 : 1.1, x: 0.7, y: 1)
                .frame(width: 112, height: max(44, CGFloat(tabHeight)), alignment: .top)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovered)
        .accessibilityLabel(isOpen ? "Hide source information" : "Show source information")
        .accessibilityValue(isOpen ? "Open" : "Closed")
        .help(isOpen ? "Hide source information" : "Show source information")
    }

    private var tabShape: RadarSourceTabShape { RadarSourceTabShape(bottomRadius: CGFloat(bottomRadius)) }

    private var backgroundColor: Color {
        let stored = isOpen ? openBackground : closedBackground
        let standard = isOpen ? ControlAppearance.tabOpenBackground : ControlAppearance.tabClosedBackground
        let dark = isOpen ? ControlAppearance.tabDarkOpenBackground : ControlAppearance.tabDarkClosedBackground
        return RadarColorHex.color(colorScheme == .dark && stored == standard ? dark : stored) ?? .gray
    }

    private var textColor: Color {
        let stored = isOpen ? openText : closedText
        let standard = isOpen ? ControlAppearance.tabOpenText : ControlAppearance.tabClosedText
        let dark = isOpen ? ControlAppearance.tabDarkOpenText : ControlAppearance.tabDarkClosedText
        return RadarColorHex.color(colorScheme == .dark && stored == standard ? dark : stored) ?? .primary
    }
}

private struct RadarSourceTabShape: InsettableShape {
    let bottomRadius: CGFloat
    private var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let frame = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let slope: CGFloat = 6
        let radius = min(bottomRadius, frame.height * 0.45)
        var path = Path()
        path.move(to: CGPoint(x: frame.minX + 1, y: frame.minY))
        path.addLine(to: CGPoint(x: frame.maxX - 1, y: frame.minY))
        path.addLine(to: CGPoint(x: frame.maxX - slope, y: frame.maxY - radius))
        path.addQuadCurve(to: CGPoint(x: frame.maxX - slope - radius, y: frame.maxY),
                          control: CGPoint(x: frame.maxX - slope, y: frame.maxY))
        path.addLine(to: CGPoint(x: frame.minX + slope + radius, y: frame.maxY))
        path.addQuadCurve(to: CGPoint(x: frame.minX + slope, y: frame.maxY - radius),
                          control: CGPoint(x: frame.minX + slope, y: frame.maxY))
        path.closeSubpath()
        return path
    }

    func inset(by amount: CGFloat) -> RadarSourceTabShape {
        var shape = self
        shape.insetAmount += amount
        return shape
    }
}
