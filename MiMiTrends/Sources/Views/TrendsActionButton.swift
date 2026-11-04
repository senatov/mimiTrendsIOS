import SwiftUI

struct TrendsActionButton: View {
    let title: String
    let systemImage: String
    var tint: Color = .blue
    var role: ButtonRole? = nil
    let action: () -> Void
    @AppStorage("controls.button.iconColor.v1") private var iconColor = ControlAppearance.buttonIconColor

    var body: some View {
        Button(role: role, action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .light))
                    .foregroundStyle(RadarColorHex.color(iconColor) ?? tint)
                    .frame(width: 18, height: 18)
                Rectangle()
                    .fill(Color.primary.opacity(0.18))
                    .frame(width: 1, height: 17)
                Text(title)
            }
            .lineLimit(1)
            .truncationMode(.tail)
        }
        .buttonStyle(TrendsActionButtonStyle(tint: tint))
        .accessibilityLabel(title)
        .help(title)
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var isHovered = false
    @AppStorage("controls.button.fontSize.v1") private var fontSize = ControlAppearance.buttonFontSize
    @AppStorage("controls.button.cornerRadius.v1") private var cornerRadius = ControlAppearance.buttonCornerRadius
    @AppStorage("controls.button.borderWidth.v1") private var borderWidth = ControlAppearance.buttonBorderWidth
    @AppStorage("controls.button.shadowRadius.v1") private var shadowRadius = ControlAppearance.buttonShadowRadius
    @AppStorage("controls.button.shadowY.v1") private var shadowY = ControlAppearance.buttonShadowY
    @AppStorage("controls.button.borderColor.v1") private var borderColor = ControlAppearance.buttonBorderColor
    @AppStorage("controls.button.shadowColor.v1") private var shadowColor = ControlAppearance.buttonShadowColor
    @AppStorage("controls.button.fontFamily.v1") private var fontFamily = ControlAppearance.buttonFontFamily
    @AppStorage("controls.button.textColor.v1") private var textColor = ControlAppearance.buttonTextColor
    @AppStorage("controls.button.backgroundColor.v1") private var backgroundColor = ControlAppearance.buttonBackgroundColor

    private var radius: CGFloat { CGFloat(cornerRadius) }

    var body: some View {
        configuration.label
            .font(buttonFont)
            .foregroundStyle(RadarColorHex.color(textColor)
                ?? ControlAppearance.contrastingTextColor(for: backgroundColor)
                ?? Color.primary.opacity(contrast == .increased ? 1 : 0.90))
            .padding(.horizontal, tiny ? 6 : compact ? 9 : 12)
            .padding(.vertical, verticalPadding)
            .frame(minWidth: minimumWidth, minHeight: minimumHeight)
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(gradient)
                    .overlay {
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .fill(tint.opacity(configuration.isPressed ? 0.12 : 0))
                    }
                    .shadow(color: resolvedShadow.opacity(shadowOpacity),
                            radius: configuration.isPressed ? 0.5 : CGFloat(shadowRadius) + (isHovered ? 2.5 : 1.25),
                            y: configuration.isPressed ? 0.5 : CGFloat(shadowY) + 0.5)
            }
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(resolvedBorder.opacity(borderOpacity),
                                  lineWidth: CGFloat(borderWidth) + 0.5)
            }
            .overlay(alignment: .top) {
                RoundedRectangle(cornerRadius: max(radius - 0.5, 0), style: .continuous)
                    .strokeBorder(.white.opacity(colorScheme == .dark ? 0.25 : 0.72), lineWidth: 1)
                    .padding(0.75)
                    .mask(alignment: .top) { Rectangle().frame(height: 12) }
                    .allowsHitTesting(false)
            }
            .opacity(isEnabled ? 1 : 0.52)
            .contentShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .onHover { isHovered = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovered)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.10), value: configuration.isPressed)
    }

    private var gradient: LinearGradient {
        let colors: [Color]
        if let custom = RadarColorHex.color(backgroundColor) {
            colors = [custom, custom]
        } else if configuration.isPressed {
            colors = [.black.opacity(0.10), .white.opacity(0.12)]
        } else if colorScheme == .dark {
            colors = [.white.opacity(isHovered ? 0.24 : 0.18), .white.opacity(0.04)]
        } else {
            colors = [.white.opacity(isHovered ? 0.76 : 0.66), Color.primary.opacity(isHovered ? 0.12 : 0.11)]
        }
        return LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
    }

    private var shadowOpacity: Double {
        if !isEnabled { return 0.04 }
        if configuration.isPressed { return 0.10 }
        return isHovered ? 0.26 : 0.20
    }

    private var borderOpacity: Double {
        if !isEnabled { return 0.10 }
        if configuration.isPressed { return 0.38 }
        return isHovered ? 0.54 : contrast == .increased ? 0.60 : 0.34
    }

    private var resolvedBorder: Color {
        RadarColorHex.color(borderColor) ?? .black
    }

    private var resolvedShadow: Color {
        RadarColorHex.color(shadowColor) ?? .black
    }

    private var buttonFont: Font {
        if dynamicTypeSize.isAccessibilitySize { return .body }
        let size = CGFloat(tiny ? max(10, fontSize - 3) : fontSize)
        let design: Font.Design = switch fontFamily {
        case "Rounded": .rounded
        case "Monospaced": .monospaced
        case "Serif": .serif
        default: .default
        }
        return .system(size: size, design: design)
    }

    private var verticalPadding: CGFloat {
        #if os(iOS)
        return tiny ? 5 : 8
        #else
        return tiny ? 2 : compact ? 4 : 7
        #endif
    }

    private var minimumHeight: CGFloat {
        #if os(iOS)
        return 44
        #else
        return tiny ? 22 : compact ? 26 : 30
        #endif
    }

    private var minimumWidth: CGFloat {
        #if os(iOS)
        return 44
        #else
        return 0
        #endif
    }
}
