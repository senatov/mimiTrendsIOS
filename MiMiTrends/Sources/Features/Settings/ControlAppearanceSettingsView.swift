import SwiftUI

struct ControlAppearanceSettingsView: View {
    @AppStorage("controls.button.fontSize.v1") private var fontSize = ControlAppearance.buttonFontSize
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
            numberRow("Font size", value: $fontSize, range: 10...20)
            numberRow("Corner radius", value: $cornerRadius, range: 0...16)
            numberRow("Border width", value: $borderWidth, range: 0...3, step: 0.25)
            numberRow("Shadow radius", value: $shadowRadius, range: 0...8, step: 0.5)
            numberRow("Shadow offset", value: $shadowY, range: 0...4, step: 0.5)
            colorRow("Border color", hex: $borderColor, fallback: "595959")
            colorRow("Shadow color", hex: $shadowColor, fallback: "000000")
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

    private func colorRow(_ title: String, hex: Binding<String>, fallback: String) -> some View {
        HStack(spacing: 12) {
            Text(title).frame(width: 180, alignment: .trailing)
            ColorPicker(title, selection: Binding(
                get: { RadarColorHex.color(hex.wrappedValue) ?? RadarColorHex.color(fallback) ?? .primary },
                set: { hex.wrappedValue = RadarColorHex.hex($0) ?? fallback }
            ), supportsOpacity: false)
            .labelsHidden()
            .frame(width: 34)
            Text(hex.wrappedValue.isEmpty ? "System default" : hex.wrappedValue.uppercased())
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
            if !hex.wrappedValue.isEmpty {
                Button("Use default", systemImage: "arrow.uturn.backward") { hex.wrappedValue = "" }
                    .labelStyle(.iconOnly)
                    .buttonStyle(TrendsActionButtonStyle(compact: true))
                    .accessibilityLabel("Restore default \(title.lowercased())")
            }
        }
    }

    private func restoreDefaults() {
        fontSize = ControlAppearance.buttonFontSize
        cornerRadius = ControlAppearance.buttonCornerRadius
        borderWidth = ControlAppearance.buttonBorderWidth
        shadowRadius = ControlAppearance.buttonShadowRadius
        shadowY = ControlAppearance.buttonShadowY
        borderColor = ControlAppearance.buttonBorderColor
        shadowColor = ControlAppearance.buttonShadowColor
    }
}
