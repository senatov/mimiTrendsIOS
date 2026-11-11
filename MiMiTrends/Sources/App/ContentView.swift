import SwiftUI

struct ContentView: View {
    @State private var showingWatchlist = false
    @State private var tableColors = RadarTableColorStore()
    @State private var tableTypography = RadarTableTypographyStore()
    @AppStorage("selected.symbol.v1") private var radarSymbol = "ORCL"
    @AppStorage("appearance.theme.v1") private var theme = "light"
    @State private var selectedTab = "radar"

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Radar", systemImage: "waveform.path.ecg", value: "radar") {
                RadarView(
                    symbol: $radarSymbol,
                    onManageWatchlist: { showingWatchlist = true },
                    onOpenProviderSettings: {
                        UserDefaults.standard.set("providers", forKey: "settings.section.v1")
                        selectedTab = "settings"
                    }
                )
            }

            Tab("Settings", systemImage: "gearshape", value: "settings") {
                SettingsView()
            }
        }
        .sheet(isPresented: $showingWatchlist) {
            WatchlistView { symbol in
                radarSymbol = symbol
                showingWatchlist = false
            }
        }
        .environment(tableColors)
        .environment(tableTypography)
        .preferredColorScheme(theme == "dark" ? .dark : theme == "light" ? .light : nil)
        .toolbar {
            #if os(macOS)
            ToolbarItem(placement: .navigation) {
                HeaderBuildBadge()
            }
            ToolbarItem(placement: .automatic) {
                HeaderResourceBadges()
            }
            #endif
        }
    }
}
