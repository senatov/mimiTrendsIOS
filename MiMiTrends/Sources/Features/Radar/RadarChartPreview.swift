import SwiftUI

struct RadarChartPreview: View {
    let symbol: String
    let companyName: String
    let companyMetadata: RadarCompanyMetadata?
    let signal: ScanResult?
    let currencyRates: DisplayCurrencyRates?
    let displayCurrency: String
    let refreshID: Int
    let providersReady: Bool
    let yahooEnabled: Bool
    let providerRevision: Int

    @Environment(\.scenePhase) private var scenePhase
    @State private var allBars: [MinuteBar] = []
    @State private var minuteProvider = "Saved Yahoo"
    @State private var yahooMinutes: (symbol: String, date: Date, bars: [MinuteBar])?
    @State private var dailyProvider = ""
    @State private var dailyBars: [MinuteBar] = []
    @State private var dailySymbol = ""
    @State private var dailyLoadedAt: Date?
    @State private var dailyError: String?
    @State private var isLoadingDaily = false
    @State private var importedTrades: [BrokerTradePosition] = []
    @AppStorage("chart.range.v1") private var rangeRaw = RadarChartRange.oneDay.rawValue
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var showingTrades = true
    @State private var showingSignalFocus = true

    private var chartData: RadarChartData {
        RadarChartData(
            allBars: convertedBars ?? [],
            range: range,
            nowEpochSeconds: Int64(Date().timeIntervalSince1970),
            focusEpochSeconds: showingSignalFocus && focusAvailable ? signalEpochSeconds : nil
        )
    }

    private var signalEpochSeconds: Int64? { signal.map { $0.signalEpochMillis / 1_000 } }

    private var focusAvailable: Bool {
        guard !range.usesDailyBars, let signalEpochSeconds else { return false }
        let bars = convertedBars ?? []
        let rangeBars: [MinuteBar]
        if range == .trades { rangeBars = bars }
        else if let seconds = range.seconds {
            rangeBars = bars.filter { $0.minuteEpochSeconds >= Int64(Date().timeIntervalSince1970) - seconds }
        } else { rangeBars = Array(bars.suffix(60)) }
        guard let nearest = RadarChartData.nearestBar(
            to: Date(timeIntervalSince1970: TimeInterval(signalEpochSeconds)), in: rangeBars
        ) else { return false }
        return abs(nearest.minuteEpochSeconds - signalEpochSeconds) <= 90
    }

    private var chartSignal: ScanResult? { range == .trades ? nil : signal }

    private var chartSignalEntryPrice: Double? {
        guard let chartSignal else { return nil }
        let source = chartSignal.priceCurrency ?? RadarChartCurrency.source(for: symbol)
        return source == displayCurrency
            ? chartSignal.signalPrice
            : currencyRates?.convert(chartSignal.signalPrice, from: source, to: displayCurrency)
    }

    private var convertedBars: [MinuteBar]? {
        let source = range.usesDailyBars ? (dailySymbol == symbol ? dailyBars : []) : allBars
        return RadarChartCurrency.bars(source, from: sourceCurrency, to: displayCurrency, rates: currencyRates)
    }

    private var range: RadarChartRange {
        RadarChartRange(rawValue: rangeRaw) ?? .oneDay
    }

    private var rangeSelection: Binding<RadarChartRange> {
        Binding(get: { range }, set: { rangeRaw = $0.rawValue })
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                chartContent(availableHeight: geometry.size.height)
                    .frame(width: max(0, geometry.size.width), alignment: .leading)
            }
        }
        .trendsPanel()
        .task(id: "\(symbol)|\(refreshID)|\(importedTrades.count)|\(range.rawValue)|\(providersReady)|\(yahooEnabled)|\(providerRevision)|\(scenePhase)") {
            guard scenePhase == .active, !range.usesDailyBars else { return }
            if !providersReady {
                await loadBars()
                return
            }
            repeat {
                await loadBars()
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
            } while !Task.isCancelled
        }
        .task(id: "daily|\(symbol)|\(range.rawValue)|\(providersReady)|\(yahooEnabled)|\(providerRevision)") {
            if providersReady { await loadDailyBarsIfNeeded() }
        }
        .task(id: "trades|\(symbol)|\(companyName)") { await loadImportedTrades() }
        .onChange(of: symbol) { _, _ in
            showingSignalFocus = true
            allBars = []
            minuteProvider = "Saved Yahoo"
        }
    }

    private func chartContent(availableHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            RadarChartHeader(
                symbol: symbol, companyName: companyName, metadata: companyMetadata,
                signal: chartSignal,
                eventBar: chartSignal?.eventCandle ?? allBars.first(where: {
                    $0.minuteEpochSeconds == (chartSignal?.signalEpochMillis ?? 0) / 1_000
                }),
                lastBar: chartData.bars.last, rates: currencyRates,
                currency: displayCurrency, hasTrades: !chartTrades.isEmpty,
                outsideTradeCount: outsideTradeCount,
                focusAvailable: focusAvailable,
                showingTrades: $showingTrades, showingSignalFocus: $showingSignalFocus, range: rangeSelection,
                onImport: { Task { await loadImportedTrades() } }
            )
            if chartTrades.count < importedTrades.count {
                Text("Some imported trades could not be converted to \(displayCurrency).")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if (range.usesDailyBars ? isLoadingDaily : isLoading) && chartData.bars.isEmpty {
                ProgressView(range.usesDailyBars ? "Loading daily price history" : "Loading chart history")
                    .frame(maxWidth: .infinity, minHeight: 180)
            } else if let message = range.usesDailyBars ? dailyError : errorMessage {
                Text(message).foregroundStyle(.red)
                    .frame(maxWidth: .infinity, minHeight: 180)
            } else if convertedBars == nil {
                ContentUnavailableView("Exchange rate unavailable", systemImage: "eurosign.arrow.circlepath",
                                       description: Text("Waiting for ECB reference rates to show this chart in \(displayCurrency)."))
                    .frame(maxWidth: .infinity, minHeight: 180)
            } else if chartData.bars.isEmpty {
                ContentUnavailableView(
                    "No prices in \(range.title)",
                    systemImage: "chart.xyaxis.line",
                    description: Text(range == .trades
                                      ? "Recent minute history is unavailable for these imported trades."
                                      : range.usesDailyBars && !yahooEnabled
                                          ? "Enable Yahoo market data to load weekly and yearly price history."
                                          : range.usesDailyBars ? "No daily prices are available for this symbol and period."
                                      : "No minute candles are available in this period. Choose Latest to view older saved candles.")
                )
                .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                RadarChartPlot(
                    data: chartData, symbol: symbol,
                    displayCurrency: displayCurrency,
                    signal: chartSignal,
                    signalEntryPrice: chartSignalEntryPrice,
                    trades: showingTrades ? chartTrades : [],
                    priceHeight: max(140, availableHeight - 180),
                    volumeHeight: 60
                )
                .id(displayCurrency)
                .zIndex(10)
                if let last = chartData.bars.last {
                    Text("\(chartData.bars.count) \(range.usesDailyBars ? "\(dailyProvider) daily" : "\(minuteProvider) minute") bars · latest \(Date(timeIntervalSince1970: TimeInterval(last.minuteEpochSeconds)).formatted(.dateTime.month().day().hour().minute())) · chart in \(chartCurrency) · trading time · closed sessions compressed")
                        .font(.subheadline.weight(.light))
                        .foregroundStyle(TrendsColors.supportingInk)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var tradeHistoryBounds: ClosedRange<Int64>? {
        guard let first = importedTrades.map(\.entryEpochSeconds).min() else { return nil }
        let now = Int64(Date().timeIntervalSince1970)
        let last = importedTrades.map { $0.exitEpochSeconds ?? now }.max() ?? now
        let lower = max(first - 1_800, now - 6 * 86_400)
        let upper = min(last + 1_800, now)
        return lower <= upper ? lower...upper : nil
    }

    private var outsideTradeCount: Int {
        guard let first = chartData.bars.first?.minuteEpochSeconds,
              let last = chartData.bars.last?.minuteEpochSeconds else { return chartTrades.count }
        return chartTrades.filter { $0.entryEpochSeconds > last || ($0.exitEpochSeconds ?? Int64.max) < first }.count
    }

    private var chartTrades: [BrokerTradePosition] {
        importedTrades.compactMap { RadarChartCurrency.trade($0, to: displayCurrency, rates: currencyRates) }
    }

    private var chartCurrency: String {
        displayCurrency
    }

    private var sourceCurrency: String { RadarChartCurrency.source(for: symbol) }

    private func loadBars() async {
        let requestedSymbol = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !requestedSymbol.isEmpty else {
            allBars = []
            return
        }
        if range == .trades && tradeHistoryBounds == nil { allBars = []; return }
        isLoading = true
        errorMessage = nil
        do {
            let historyBounds = range == .trades ? tradeHistoryBounds : nil
            let loaded = try await Task.detached(priority: .userInitiated) {
                let store = try MarketBarStore(url: MarketBarStore.defaultURL())
                return try await store.loadRecentMinuteBars(
                    symbol: requestedSymbol,
                    fromEpochSeconds: historyBounds?.lowerBound ?? 0,
                    throughEpochSeconds: historyBounds?.upperBound ?? Int64(Date().timeIntervalSince1970),
                    limit: 2_000
                )
            }.value
            guard !Task.isCancelled else { return }
            var visibleBars = loaded
            var provider = "Saved Yahoo"
            if providersReady, yahooEnabled, range != .trades, !hasBarsInRange(loaded) {
                let fallback = await yahooMinuteHistory(symbol: requestedSymbol)
                guard !Task.isCancelled else { return }
                if hasBarsInRange(fallback) {
                    visibleBars = fallback
                    provider = "Yahoo historical"
                }
            }
            allBars = visibleBars
            minuteProvider = provider
        } catch {
            guard !Task.isCancelled else { return }
            allBars = []
            errorMessage = error.localizedDescription
            AppDiagnostics.shared.record(
                .error, "RadarChart", "bars-load-failed",
                "symbol=\(requestedSymbol) error=\(String(describing: type(of: error)))"
            )
        }
        isLoading = false
    }

    private func hasBarsInRange(_ bars: [MinuteBar]) -> Bool {
        guard let latest = bars.last else { return false }
        guard let seconds = range.seconds else { return true }
        return latest.minuteEpochSeconds >= Int64(Date().timeIntervalSince1970) - seconds
    }

    private func yahooMinuteHistory(symbol: String) async -> [MinuteBar] {
        if let cache = yahooMinutes, cache.symbol == symbol, Date().timeIntervalSince(cache.date) < 60 {
            return cache.bars
        }
        do {
            let bars = try await YahooRadarSource().minuteBars(symbol: symbol, includeExtendedHours: true)
            guard !Task.isCancelled else { return [] }
            yahooMinutes = (symbol, Date(), bars)
            return bars
        } catch {
            guard !Task.isCancelled else { return [] }
            yahooMinutes = (symbol, Date(), [])
            AppDiagnostics.shared.record(.warning, "RadarChart", "yahoo-history-unavailable",
                "symbol=\(symbol) error=\(String(describing: type(of: error)))")
            return []
        }
    }

    private func loadDailyBarsIfNeeded() async {
        guard range.usesDailyBars else { return }
        let requestedSymbol = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !requestedSymbol.isEmpty else { return }
        if yahooEnabled, dailySymbol == requestedSymbol, hasBarsInRange(dailyBars),
           let dailyLoadedAt,
           Date().timeIntervalSince(dailyLoadedAt) < 15 * 60 { return }
        isLoadingDaily = true
        defer { isLoadingDaily = false }
        dailyError = nil
        guard yahooEnabled else {
            dailyBars = []
            dailySymbol = requestedSymbol
            dailyProvider = ""
            dailyLoadedAt = nil
            return
        }
        do {
            let bars = try await YahooRadarSource().dailyBars(symbol: requestedSymbol)
            guard !Task.isCancelled else { return }
            dailyBars = bars
            dailyProvider = "Yahoo historical"
            dailySymbol = requestedSymbol
            dailyLoadedAt = .now
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            dailyBars = []
            dailyError = error.localizedDescription
            AppDiagnostics.shared.record(.warning, "RadarChart", "daily-history-failed",
                                         "symbol=\(requestedSymbol) error=\(String(describing: type(of: error)))")
        }
    }

    private func loadImportedTrades() async {
        let requestedSymbol = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !requestedSymbol.isEmpty else {
            importedTrades = []
            return
        }
        do {
            let requestedName = companyName
            let positions = try await Task.detached(priority: .utility) {
                let store = try BrokerTransactionStore(url: BrokerTransactionStore.defaultURL())
                let executions = try await store.loadExecutedTransactions()
                return BrokerTradeChartMatcher.positions(
                    symbol: requestedSymbol, companyName: requestedName, executions: executions
                )
            }.value
            guard !Task.isCancelled else { return }
            importedTrades = positions
        } catch {
            guard !Task.isCancelled else { return }
            importedTrades = []
            AppDiagnostics.shared.record(
                .warning, "RadarChart", "trades-load-failed",
                "symbol=\(requestedSymbol) error=\(String(describing: type(of: error)))"
            )
        }
    }
}
