import SwiftUI

/// Keeps quote signals and primary-listing candles separate while making candles the default.
struct RadarInstrumentChart: View {
    let symbol: String
    let companyName: String
    let companyMetadata: RadarCompanyMetadata?
    let signal: ScanResult?
    let currencyRates: DisplayCurrencyRates?
    let displayCurrency: String
    let refreshID: Int
    let providersReady: Bool
    let yahooEnabled: Bool
    let fmpEnabled: Bool
    let providerRevision: Int
    @State private var retryID = 0
    @State private var resolvedSymbol: String?
    @State private var resolutionError: String?
    @State private var showingQuotes = false
    @State private var showingSignalFocus = true
    @AppStorage("chart.range.v1") private var rangeRaw = RadarChartRange.oneDay.rawValue

    var body: some View {
        if !symbol.hasPrefix("LS:") {
            candles(symbol: symbol, signal: signal)
        } else {
            VStack(spacing: 4) {
                HStack(spacing: 8) {
                    TrendsActionButton(title: "Candles", systemImage: "chart.bar.xaxis",
                                       tint: showingQuotes ? .blue : .purple) { showingQuotes = false }
                        .disabled(!yahooEnabled)
                    TrendsActionButton(title: "L&S quotes", systemImage: "waveform.path",
                                       tint: showingQuotes ? .purple : .blue) { showingQuotes = true }
                    if let resolvedSymbol {
                        Text("\(symbol) quote signal · \(resolvedSymbol) primary-listing candles")
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                if showingQuotes || !yahooEnabled {
                    LSQuoteHistoryChart(symbol: symbol, companyName: companyName, refreshID: refreshID,
                        range: Binding(get: { RadarChartRange(rawValue: rangeRaw) ?? .oneDay },
                                       set: { rangeRaw = $0.rawValue }),
                        signal: signal, showingSignalFocus: $showingSignalFocus)
                } else if let resolvedSymbol {
                    // L&S execution prices belong to another venue; do not plot them as Yahoo trade prices.
                    candles(symbol: resolvedSymbol, signal: nil)
                } else if let resolutionError {
                    VStack {
                        ContentUnavailableView("Candles unavailable", systemImage: "chart.bar.xaxis",
                            description: Text(resolutionError + " L&S quotes remain available above."))
                        TrendsActionButton(title: "Retry candles", systemImage: "arrow.clockwise") { retryID += 1 }
                    }
                } else {
                    ProgressView("Finding the candle listing…").frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .task(id: "\(symbol)|\(providersReady)|\(yahooEnabled)|\(providerRevision)|\(retryID)") {
                resolvedSymbol = nil
                resolutionError = nil
                guard providersReady, yahooEnabled else { return }
                do {
                    let result = try await LSChartInstrumentResolver.shared.resolve(symbol)
                    guard !Task.isCancelled else { return }
                    resolvedSymbol = result
                } catch {
                    guard !Task.isCancelled else { return }
                    resolutionError = MarketRadarErrorDescription.message(error, provider: "Candle listing")
                    AppDiagnostics.shared.record(.warning, "RadarChart", "ls-candle-resolution-failed",
                                                 "instrument=\(symbol) error=\(String(describing: error))")
                }
            }
        }
    }

    private func candles(symbol: String, signal: ScanResult?) -> some View {
        RadarChartPreview(symbol: symbol, companyName: companyName, companyMetadata: companyMetadata,
            signal: signal, currencyRates: currencyRates, displayCurrency: displayCurrency,
            refreshID: refreshID, providersReady: providersReady, yahooEnabled: yahooEnabled,
            fmpEnabled: fmpEnabled, providerRevision: providerRevision)
    }
}
