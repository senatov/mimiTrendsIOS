import SwiftUI

struct ContentView: View {
    @Environment(RadarSession.self) private var radarSession
    @State private var showingWatchlist = false
    @State private var watchlistRevision = 0
    @State private var tableColors = RadarTableColorStore()
    @State private var tableTypography = RadarTableTypographyStore()
    @AppStorage("selected.symbol.v1") private var radarSymbol = "ORCL"
    @AppStorage("appearance.theme.v1") private var theme = "light"

    var body: some View {
        TabView {
            Tab("Radar", systemImage: "waveform.path.ecg") {
                RadarView(symbol: $radarSymbol, watchlistRevision: watchlistRevision) {
                    showingWatchlist = true
                }
            }

            Tab("Settings", systemImage: "gearshape") {
                SettingsView()
            }
        }
        .sheet(isPresented: $showingWatchlist, onDismiss: { watchlistRevision += 1 }) {
            WatchlistView { symbol in
                radarSession.stop()
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
