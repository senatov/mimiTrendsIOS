import SwiftUI

struct RadarHeader: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    @Binding var symbol: String
    @Binding var scanWatchlist: Bool
    let session: RadarSession
    let setupMessage: String?
    let isPreparingFeed: Bool
    let sourcesOpen: Bool
    let watchlist: [WatchlistEntry]
    let onManageWatchlist: () -> Void
    let onToggleFeed: () -> Void
    let onToggleSources: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            headerLayout {
                HStack(spacing: 10) { feedControls }
                if !isCompactLayout { Spacer(minLength: 8) }
                scopeControls
            }
            Text(feedScopeDescription)
                .font(.footnote)
                .foregroundStyle(TrendsColors.supportingInk)
                .accessibilityIdentifier("finnhubFeedScopeDescription")
            if let message = setupMessage ?? session.errorMessage {
                Text(message).font(.footnote).foregroundStyle(.red)
            }
        }
        .trendsPanel()
        .overlay(alignment: .bottomTrailing) {
            RadarSourceTab(isOpen: sourcesOpen, action: onToggleSources)
                .offset(x: -12, y: 44)
        }
    }

    private var isCompactLayout: Bool {
        #if os(iOS)
        dynamicTypeSize.isAccessibilitySize || horizontalSizeClass == .compact
        #else
        dynamicTypeSize.isAccessibilitySize
        #endif
    }

    private func headerLayout<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        Group {
            if isCompactLayout {
                VStack(alignment: .leading, spacing: 7) { content() }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) { content() }
                    VStack(alignment: .leading, spacing: 7) { content() }
                }
            }
        }
    }

    @ViewBuilder
    private var feedControls: some View {
        TextField("Ticker symbol", text: $symbol)
            .textFieldStyle(.roundedBorder)
            .autocorrectionDisabled()
            .frame(maxWidth: 240)
            .accessibilityLabel("Radar symbol")
        TrendsActionButton(
            title: session.isScanning ? "Stop feed" : isPreparingFeed ? "Preparing" : "Start feed",
            systemImage: session.isScanning ? "stop.fill" : "play.fill",
            tint: session.isScanning ? .red : .green
        ) { onToggleFeed() }
        .disabled(isPreparingFeed || (!session.isScanning && symbol.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
    }

    private var scopePicker: some View {
        Picker("Finnhub feed scope", selection: $scanWatchlist) {
            Text("Selected only").tag(false)
            Text("Selected + saved").tag(true)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(maxWidth: 310)
        .disabled(session.isScanning || isPreparingFeed)
        .help("Choose which symbols Finnhub subscribes to when you start the feed. Lang & Schwarz scans independently.")
    }

    private var scopeControls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { scopePicker; manageWatchlistButton }
            VStack(alignment: .leading, spacing: 7) { scopePicker; manageWatchlistButton }
        }
    }

    private var manageWatchlistButton: some View {
        TrendsActionButton(title: "Edit watchlist", systemImage: "star", action: onManageWatchlist)
            .accessibilityIdentifier("editWatchlistButton")
    }

    private var feedScopeDescription: String {
        if session.isScanning {
            return "Finnhub feed: \(session.targetSymbols.joined(separator: ", ")). Lang & Schwarz scans independently."
        }
        guard !isPreparingFeed else { return "Preparing Finnhub feed…" }
        guard let selection = try? FinnhubWatchlistSelection(
            selectedSymbol: symbol, includeWatchlist: scanWatchlist, watchlist: watchlist
        ) else { return "Enter a valid symbol to start the Finnhub feed." }
        if scanWatchlist && selection.symbols.count == 1 {
            return "Finnhub feed: \(selection.symbols[0]). No other supported symbols in Watchlist. Start feed to apply."
        }
        return "Finnhub feed: \(selection.symbols.joined(separator: ", ")). Start feed to apply; Lang & Schwarz scans independently."
    }
}
