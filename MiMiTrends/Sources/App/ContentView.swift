import SwiftUI

struct ContentView: View {
    @Environment(RadarSession.self) private var radarSession
    @State private var selectedTab = "radar"
    @State private var tableColors = RadarTableColorStore()
    @State private var tableTypography = RadarTableTypographyStore()
    @AppStorage("selected.symbol.v1") private var radarSymbol = "ORCL"
    @AppStorage("appearance.theme.v1") private var theme = "light"

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Radar", systemImage: "waveform.path.ecg", value: "radar") {
                RadarView(symbol: $radarSymbol)
            }

            Tab("Watchlist", systemImage: "star", value: "watchlist") {
                WatchlistView { symbol in
                    radarSession.stop()
                    radarSymbol = symbol
                    selectedTab = "radar"
                }
            }

            Tab("Settings", systemImage: "gearshape", value: "settings") {
                SettingsView()
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
