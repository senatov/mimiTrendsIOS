import SwiftUI

struct ControlAppearanceSettingsView: View {
    @AppStorage("controls.button.fontSize.v1") private var buttonFontSize = ControlAppearance.buttonFontSize
    @AppStorage("controls.button.cornerRadius.v1") private var buttonCornerRadius = ControlAppearance.buttonCornerRadius
    @AppStorage("controls.tab.fontSize.v1") private var tabFontSize = ControlAppearance.tabFontSize
    @AppStorage("controls.tab.height.v1") private var tabHeight = ControlAppearance.tabHeight
    @AppStorage("controls.tab.bottomRadius.v1") private var tabBottomRadius = ControlAppearance.tabBottomRadius
    @AppStorage("controls.tab.openBackground.v1") private var tabOpenBackground = ControlAppearance.tabOpenBackground
    @AppStorage("controls.tab.closedBackground.v1") private var tabClosedBackground = ControlAppearance.tabClosedBackground
    @AppStorage("controls.tab.openText.v1") private var tabOpenText = ControlAppearance.tabOpenText
    @AppStorage("controls.tab.closedText.v1") private var tabClosedText = ControlAppearance.tabClosedText

    var body: some View {
        SettingsGroup(title: "Action buttons") {
            numberRow("Font size", value: $buttonFontSize, range: 10...20)
            numberRow("Corner radius", value: $buttonCornerRadius, range: 4...16)
            TrendsActionButton(title: "Preview button", systemImage: "star") {}
                .allowsHitTesting(false)
        }
        SettingsGroup(title: "Sources tab") {
            numberRow("Font size", value: $tabFontSize, range: 11...18)
            numberRow("Height", value: $tabHeight, range: 24...40)
            numberRow("Bottom corner radius", value: $tabBottomRadius, range: 4...12)
            colorRow("Open background", hex: $tabOpenBackground, fallback: ControlAppearance.tabOpenBackground)
            colorRow("Closed background", hex: $tabClosedBackground, fallback: ControlAppearance.tabClosedBackground)
            colorRow("Open text", hex: $tabOpenText, fallback: ControlAppearance.tabOpenText)
            colorRow("Closed text", hex: $tabClosedText, fallback: ControlAppearance.tabClosedText)
            HStack(spacing: 12) {
                RadarSourceTab(isOpen: true) {}
                RadarSourceTab(isOpen: false) {}
            }
            .allowsHitTesting(false)
            .accessibilityLabel("Sources tab appearance preview")
        }
        Button("Restore button and tab defaults", systemImage: "arrow.uturn.backward") {
            restoreDefaults()
        }
        .buttonStyle(TrendsActionButtonStyle(compact: true))
    }

    private func numberRow(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        HStack(spacing: 12) {
            Text(title).frame(width: 180, alignment: .trailing)
            Stepper(value: value, in: range, step: 1) {
                Text("\(Int(value.wrappedValue)) pt")
                    .monospacedDigit()
                    .frame(width: 52, alignment: .leading)
            }
            .frame(maxWidth: 180, alignment: .leading)
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
            Text(hex.wrappedValue.uppercased())
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    private func restoreDefaults() {
        buttonFontSize = ControlAppearance.buttonFontSize
        buttonCornerRadius = ControlAppearance.buttonCornerRadius
        tabFontSize = ControlAppearance.tabFontSize
        tabHeight = ControlAppearance.tabHeight
        tabBottomRadius = ControlAppearance.tabBottomRadius
        tabOpenBackground = ControlAppearance.tabOpenBackground
        tabClosedBackground = ControlAppearance.tabClosedBackground
        tabOpenText = ControlAppearance.tabOpenText
        tabClosedText = ControlAppearance.tabClosedText
    }
}
