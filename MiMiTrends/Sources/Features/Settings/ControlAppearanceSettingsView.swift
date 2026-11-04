import SwiftUI

struct ControlAppearanceSettingsView: View {
    @AppStorage("controls.button.fontFamily.v1") private var fontFamily = ControlAppearance.buttonFontFamily
    @AppStorage("controls.button.fontSize.v1") private var fontSize = ControlAppearance.buttonFontSize
    @AppStorage("controls.button.textColor.v1") private var textColor = ControlAppearance.buttonTextColor
    @AppStorage("controls.button.iconColor.v1") private var iconColor = ControlAppearance.buttonIconColor
    @AppStorage("controls.button.backgroundColor.v1") private var backgroundColor = ControlAppearance.buttonBackgroundColor
    @AppStorage("controls.button.cornerRadius.v1") private var cornerRadius = ControlAppearance.buttonCornerRadius
    @AppStorage("controls.button.borderWidth.v1") private var borderWidth = ControlAppearance.buttonBorderWidth
    @AppStorage("controls.button.shadowRadius.v1") private var shadowRadius = ControlAppearance.buttonShadowRadius
    @AppStorage("controls.button.shadowY.v1") private var shadowY = ControlAppearance.buttonShadowY
    @AppStorage("controls.button.borderColor.v1") private var borderColor = ControlAppearance.buttonBorderColor
    @AppStorage("controls.button.shadowColor.v1") private var shadowColor = ControlAppearance.buttonShadowColor

    var body: some View {
        SettingsGroup(title: "Action buttons") {
            Text("Button appearance applies across Radar, Watchlist and Settings.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Text("Font family").frame(width: 180, alignment: .trailing)
                Picker("Font family", selection: $fontFamily) {
                    Text("System").tag("System")
                    Text("Rounded").tag("Rounded")
                    Text("Monospaced").tag("Monospaced")
                    Text("Serif").tag("Serif")
                }
                .labelsHidden()
                .frame(maxWidth: 200, alignment: .leading)
                Spacer(minLength: 0)
            }
            numberRow("Font size", value: $fontSize, range: 10...20)
            colorRow("Text color", hex: $textColor, factoryHex: ControlAppearance.buttonTextColor,
                     fallback: ControlAppearance.contrastingTextColor(for: backgroundColor) ?? .primary,
                     emptyLabel: "Automatic contrast")
            colorRow("Icon color", hex: $iconColor, factoryHex: ControlAppearance.buttonIconColor, fallback: .blue)
            colorRow("Background color", hex: $backgroundColor, factoryHex: ControlAppearance.buttonBackgroundColor,
                     fallback: SettingsColors.group)
            Text("These factory colors apply to new installations. Restore defaults returns to this palette.")
                .font(.caption)
                .foregroundStyle(.secondary)
            numberRow("Corner radius", value: $cornerRadius, range: 0...16)
            numberRow("Border width", value: $borderWidth, range: 0...3, step: 0.25)
            numberRow("Shadow radius", value: $shadowRadius, range: 0...8, step: 0.5)
            numberRow("Shadow offset", value: $shadowY, range: 0...4, step: 0.5)
            colorRow("Border color", hex: $borderColor, factoryHex: ControlAppearance.buttonBorderColor, fallback: .gray)
            colorRow("Shadow color", hex: $shadowColor, factoryHex: ControlAppearance.buttonShadowColor, fallback: .black)
            HStack(spacing: 10) {
                TrendsActionButton(title: "Sources", systemImage: "sidebar.right") {}
                TrendsActionButton(title: "Refresh", systemImage: "arrow.clockwise") {}
                TrendsActionButton(title: "Remove", systemImage: "trash", tint: .red) {}
            }
            .allowsHitTesting(false)
            .accessibilityLabel("Action button appearance preview")
        }
        TrendsActionButton(title: "Restore button defaults", systemImage: "arrow.uturn.backward") {
            restoreDefaults()
        }
    }

    private func numberRow(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double = 1) -> some View {
        HStack(spacing: 12) {
            Text(title).frame(width: 180, alignment: .trailing)
            Stepper(value: value, in: range, step: step) {
                Text(value.wrappedValue.formatted(.number.precision(.fractionLength(step < 1 ? 2 : 0))) + " pt")
                    .monospacedDigit()
                    .frame(width: 70, alignment: .leading)
            }
            .frame(maxWidth: 200, alignment: .leading)
            Spacer(minLength: 0)
        }
    }

    private func colorRow(_ title: String, hex: Binding<String>, factoryHex: String,
                          fallback: Color, emptyLabel: String = "System default") -> some View {
        HStack(spacing: 12) {
            Text(title).frame(width: 180, alignment: .trailing)
            ColorPicker(title, selection: Binding(
                get: { RadarColorHex.color(hex.wrappedValue) ?? fallback },
                set: { hex.wrappedValue = RadarColorHex.hex($0) ?? "" }
            ), supportsOpacity: false)
            .labelsHidden()
            .frame(width: 34)
            Text(hex.wrappedValue.isEmpty ? emptyLabel : hex.wrappedValue.uppercased())
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
            if hex.wrappedValue.caseInsensitiveCompare(factoryHex) != .orderedSame {
                Button("Use default", systemImage: "arrow.uturn.backward") { hex.wrappedValue = factoryHex }
                    .labelStyle(.iconOnly)
                    .buttonStyle(TrendsActionButtonStyle(compact: true))
                    .accessibilityLabel("Restore default \(title.lowercased())")
            }
        }
    }

    private func restoreDefaults() {
        fontFamily = ControlAppearance.buttonFontFamily
        fontSize = ControlAppearance.buttonFontSize
        textColor = ControlAppearance.buttonTextColor
        iconColor = ControlAppearance.buttonIconColor
        backgroundColor = ControlAppearance.buttonBackgroundColor
        cornerRadius = ControlAppearance.buttonCornerRadius
        borderWidth = ControlAppearance.buttonBorderWidth
        shadowRadius = ControlAppearance.buttonShadowRadius
        shadowY = ControlAppearance.buttonShadowY
        borderColor = ControlAppearance.buttonBorderColor
        shadowColor = ControlAppearance.buttonShadowColor
    }
}
