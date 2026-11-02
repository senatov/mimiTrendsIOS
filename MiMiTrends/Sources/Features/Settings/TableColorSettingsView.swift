import SwiftUI

struct TableColorSettingsView: View {
    @Environment(RadarTableColorStore.self) private var colors
    @Environment(RadarTableTypographyStore.self) private var typography
    @Environment(\.colorScheme) private var colorScheme
    @State private var fontName = RadarTableTypographyStore.defaultFontName

    var body: some View {
        SettingsPage(title: "Color Table", subtitle: "Table colors and typography") { _ in
            typographyGroup
            tableGroup(
                "Live radar",
                colors: [.signalTableFill, .signalHeaderFill, .signalHeaderText, .signalGrid,
                         .signalBodyText, .signalMutedText, .signalRowFill,
                         .rise, .fall, .selectedRow, .criticalRow, .signalActionAccent]
            )
            tableGroup(
                "Source telemetry",
                colors: [.sourceTableFill, .sourceHeaderFill, .sourceHeaderText, .sourceGrid,
                         .sourceBodyText, .sourceMutedText, .sourceRowFill,
                         .sourceActive, .sourceAttention, .sourceInactive, .sourceActionAccent]
            )
            Button("Restore all table colors and fonts", systemImage: "arrow.uturn.backward") {
                colors.resetAll()
                typography.reset()
                fontName = RadarTableTypographyStore.defaultFontName
            }
            .buttonStyle(TrendsActionButtonStyle(compact: true))
        }
        .onAppear { fontName = typography.fontName }
        .onChange(of: fontName) { _, value in typography.fontName = value }
    }

    private var typographyGroup: some View {
        SettingsGroup(title: "Table font") {
            HStack(spacing: 12) {
                Text("Font family")
                    .frame(width: 150, alignment: .trailing)
                TextField("System", text: $fontName)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 300)
                    .help("Enter a font family name, or use System")
            }
            HStack(spacing: 12) {
                Text("Font size")
                    .frame(width: 150, alignment: .trailing)
                Stepper(value: Binding(
                    get: { typography.size },
                    set: { typography.size = $0 }
                ), in: 10...20, step: 1) {
                    Text("\(Int(typography.size)) pt")
                        .monospacedDigit()
                        .frame(width: 52, alignment: .leading)
                }
                .frame(maxWidth: 180, alignment: .leading)
            }
            HStack {
                Text("Preview")
                    .frame(width: 150, alignment: .trailing)
                Text("Company name    ↑ SUSTAINED RISE    +3.25% / 45m")
                    .font(typography.font)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(SettingsColors.group, in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    private func tableGroup(_ title: String, colors roles: [RadarTableColorRole]) -> some View {
        SettingsGroup(title: title) {
            ForEach(roles) { role in
                colorRow(role)
            }
        }
    }

    private func colorRow(_ role: RadarTableColorRole) -> some View {
        HStack(spacing: 12) {
            Text(role.title)
                .frame(width: 190, alignment: .trailing)
            RoundedRectangle(cornerRadius: 3)
                .fill(role.defaultColor(dark: colorScheme == .dark))
                .frame(width: 24, height: 18)
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(.primary.opacity(0.16), lineWidth: 0.5))
                .help("Default color")
            Text("→")
                .foregroundStyle(.secondary)
            ColorPicker(role.title, selection: Binding(
                get: { colors.color(role, dark: colorScheme == .dark) },
                set: { colors.set($0, for: role) }
            ), supportsOpacity: false)
            .labelsHidden()
            .frame(width: 34)
            Text(colors.hexValue(for: role) ?? (colorScheme == .dark ? role.defaultHexDark : role.defaultHexLight))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)
            if colors.isCustomized(role) {
                Button("Restore \(role.title)", systemImage: "arrow.uturn.backward") {
                    colors.reset(role)
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
            }
            Spacer(minLength: 0)
        }
        .font(.body)
        .padding(.vertical, 3)
    }
}
