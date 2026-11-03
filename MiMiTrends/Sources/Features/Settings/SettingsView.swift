import SwiftUI

struct SettingsView: View {
    @AppStorage("settings.section.v1") private var selectedSection = SettingsSection.scanner.rawValue

    private var sectionSelection: Binding<String?> {
        Binding(
            get: { selectedSection },
            set: { if let section = $0 { selectedSection = section } }
        )
    }

    var body: some View {
        NavigationSplitView {
            List(selection: sectionSelection) {
                Section {
                    ForEach(SettingsSection.allCases) { section in
                        NavigationLink(value: section.rawValue) {
                            Label(section.title, systemImage: section.symbol)
                                .font(.body.weight(.light))
                                .foregroundStyle(selectedSection == section.rawValue ? .white : TrendsColors.ink)
                        }
                        .listRowBackground(selectedSection == section.rawValue ? Color.blue : Color.clear)
                    }
                } header: {
                    Text("Preferences")
                        .font(.subheadline.weight(.light))
                        .foregroundStyle(TrendsColors.supportingInk)
                }
            }
            .navigationTitle("Settings")
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 210, ideal: 240, max: 300)
        } detail: {
            switch SettingsSection(rawValue: selectedSection) ?? .scanner {
            case .scanner:
                ScannerSettingsView()
            case .rapidMoves:
                RadarScanSettingsView()
            case .providers:
                SourceCredentialsView()
            case .currency:
                CurrencySettingsView()
            case .appearance:
                AppearanceSettingsView()
            case .tableColors:
                TableColorSettingsView()
            }
        }
        .navigationSplitViewStyle(.balanced)
    }
}

private enum SettingsSection: String, CaseIterable, Identifiable {
    case scanner, rapidMoves, providers, currency, appearance, tableColors

    var id: String { rawValue }

    var title: String {
        switch self {
        case .scanner: "Scanner"
        case .rapidMoves: "Rapid moves"
        case .providers: "Market data providers"
        case .currency: "Currency"
        case .appearance: "Appearance"
        case .tableColors: "Color Table"
        }
    }

    var symbol: String {
        switch self {
        case .scanner: "line.3.horizontal.decrease.circle"
        case .rapidMoves: "waveform.path.ecg"
        case .providers: "antenna.radiowaves.left.and.right"
        case .currency: "eurosign.circle"
        case .appearance: "paintpalette"
        case .tableColors: "tablecells"
        }
    }
}
