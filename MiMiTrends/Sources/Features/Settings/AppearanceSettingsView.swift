import SwiftUI

struct AppearanceSettingsView: View {
    @Environment(RadarTableColorStore.self) private var tableColors
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("appearance.theme.v1") private var theme = "light"

    var body: some View {
        SettingsPage(title: "Appearance", subtitle: "Workspace colour and system typography") { width in
            if width >= 900 {
                HStack(alignment: .top, spacing: 18) {
                    workspaceGroup
                    typographyGroup
                }
            } else {
                workspaceGroup
                typographyGroup
            }
            tableColorGroup
        }
    }

    private var workspaceGroup: some View {
        SettingsGroup(title: "Workspace") {
            Picker("Theme", selection: $theme) {
                Text("System").tag("system")
                Text("Light").tag("light")
                Text("Dark").tag("dark")
            }
            .pickerStyle(.segmented)
        }
    }

    private var typographyGroup: some View {
        SettingsGroup(title: "Typography and layout") {
            SettingsValueRow(title: "Font", value: "System")
            SettingsValueRow(title: "Text size", value: "Follows device settings")
            SettingsValueRow(title: "Panels", value: "Resizable; positions saved")
            Text("Text follows the system size. Radar and Settings use the prototype's high-contrast text colours.")
                .font(.body.weight(.light))
                .foregroundStyle(TrendsColors.supportingInk)
        }
    }

    private var tableColorGroup: some View {
        SettingsGroup(title: "Radar table colors") {
            Text("Choose colors for both Radar tables. Changes appear immediately and are saved for the next launch.")
                .font(.subheadline)
                .foregroundStyle(TrendsColors.supportingInk)
            colorSection("Structure and text", roles: [
                .headerFill, .headerText, .grid, .bodyText, .mutedText
            ])
            colorSection("Signals", roles: [
                .rise, .fall, .selectedRow, .criticalRow
            ])
            colorSection("Sources and actions", roles: [
                .sourceActive, .sourceAttention, .sourceInactive, .actionAccent
            ])
            Button("Restore all table colors", systemImage: "arrow.uturn.backward") {
                tableColors.resetAll()
            }
            .buttonStyle(TrendsActionButtonStyle(compact: true))
        }
    }

    private func colorSection(_ title: String, roles: [RadarTableColorRole]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            ForEach(roles) { role in
                HStack(spacing: 10) {
                    Text(role.title)
                    Spacer(minLength: 8)
                    ColorPicker(role.title, selection: Binding(
                        get: { tableColors.color(role, dark: colorScheme == .dark) },
                        set: { tableColors.set($0, for: role) }
                    ), supportsOpacity: false)
                    .labelsHidden()
                    .accessibilityLabel(role.title)
                    if tableColors.isCustomized(role) {
                        Button("Restore \(role.title)", systemImage: "arrow.uturn.backward") {
                            tableColors.reset(role)
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                    }
                }
                .font(.body)
            }
        }
        .padding(.vertical, 4)
    }
}
