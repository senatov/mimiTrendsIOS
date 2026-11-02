import SwiftUI

struct AppearanceSettingsView: View {
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

}
