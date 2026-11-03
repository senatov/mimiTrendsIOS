import SwiftUI

struct TrendsActionButton: View {
    let title: String
    let systemImage: String
    var tint: Color = .blue
    var role: ButtonRole? = nil
    let action: () -> Void

    var body: some View {
        Button(role: role, action: action) {
            Label {
                Text(title).foregroundStyle(.primary)
            } icon: {
                Image(systemName: systemImage).foregroundStyle(tint)
            }
            .lineLimit(1)
        }
        .buttonStyle(TrendsActionButtonStyle(tint: tint))
    }
}

struct TrendsActionButtonStyle: ButtonStyle {
    var tint: Color = .blue
    var compact = true
    var tiny = false

    func makeBody(configuration: Configuration) -> some View {
        TrendsActionButtonBody(configuration: configuration, tint: tint, compact: compact, tiny: tiny)
    }
}

private struct TrendsActionButtonBody: View {
    let configuration: TrendsActionButtonStyle.Configuration
    let tint: Color
    let compact: Bool
    let tiny: Bool

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var isHovered = false

    private let cornerRadius: CGFloat = 9

    var body: some View {
        configuration.label
            .font(buttonFont)
            .padding(.horizontal, tiny ? 6 : compact ? 10 : 12)
            .frame(minWidth: minimumWidth, minHeight: minimumHeight)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.regularMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(LinearGradient(
                                colors: gradientColors,
                                startPoint: .top,
                                endPoint: .bottom
                            ))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(tint.opacity(configuration.isPressed ? 0.12 : (isHovered ? 0.10 : 0.05)))
                    }
                    .shadow(
                        color: .black.opacity(configuration.isPressed ? 0.05 : (isHovered ? 0.20 : 0.13)),
                        radius: configuration.isPressed ? 1 : (isHovered ? 5 : 3),
                        y: configuration.isPressed ? 0 : 2
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        Color.primary.opacity(contrast == .increased ? 0.45 : (isHovered ? 0.28 : 0.18)),
                        lineWidth: 1
                    )
            }
            .overlay(alignment: .top) {
                RoundedRectangle(cornerRadius: cornerRadius - 1, style: .continuous)
                    .strokeBorder(.white.opacity(colorScheme == .dark ? 0.25 : 0.70), lineWidth: 1)
                    .padding(1)
                    .mask(alignment: .top) { Rectangle().frame(height: 12) }
                    .allowsHitTesting(false)
            }
            .opacity(isEnabled ? 1 : 0.48)
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .onHover { isHovered = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovered)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.10), value: configuration.isPressed)
    }

    private var buttonFont: Font {
        #if os(iOS)
        tiny ? .system(size: 11, weight: .ultraLight) : .body
        #else
        tiny ? .system(size: 10, weight: .ultraLight) : .body
        #endif
    }

    private var minimumHeight: CGFloat {
        #if os(iOS)
        44
        #else
        tiny ? 20 : compact ? 24 : 30
        #endif
    }

    private var minimumWidth: CGFloat {
        #if os(iOS)
        44
        #else
        0
        #endif
    }

    private var gradientColors: [Color] {
        if configuration.isPressed {
            return [.black.opacity(0.08), .white.opacity(0.05)]
        }
        if colorScheme == .dark {
            return [.white.opacity(isHovered ? 0.20 : 0.14), .black.opacity(0.04)]
        }
        return [.white.opacity(isHovered ? 0.58 : 0.45), .black.opacity(0.07)]
    }
}
