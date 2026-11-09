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
    let fmpEnabled: Bool
    let providerRevision: Int

    @State private var allBars: [MinuteBar] = []
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
    @State private var cursorInspection: RadarChartInspection?
    @State private var showingTrades = true

    private var chartData: RadarChartData {
        RadarChartData(
            allBars: convertedBars ?? [],
            range: range,
            nowEpochSeconds: Int64(Date().timeIntervalSince1970)
        )
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
        Group {
            if symbol.hasPrefix("LS:") {
                LSQuoteHistoryChart(symbol: symbol, companyName: companyName, refreshID: refreshID)
            } else {
                GeometryReader { geometry in
                    ScrollView { chartContent(availableHeight: geometry.size.height) }
                }
                .trendsPanel()
            }
        }
        .task(id: "\(symbol)|\(refreshID)|\(importedTrades.count)|\(range.rawValue)|\(providersReady)|\(yahooEnabled)|\(providerRevision)") {
            if providersReady, !symbol.hasPrefix("LS:") { await loadBars() }
        }
        .task(id: "daily|\(symbol)|\(range.rawValue)|\(providersReady)|\(yahooEnabled)|\(fmpEnabled)|\(providerRevision)") {
            if providersReady, !symbol.hasPrefix("LS:") { await loadDailyBarsIfNeeded() }
        }
        .task(id: "trades|\(symbol)|\(companyName)") { if !symbol.hasPrefix("LS:") { await loadImportedTrades() } }
        .onChange(of: displayCurrency) { _, _ in cursorInspection = nil }
    }

    private func chartContent(availableHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            RadarChartHeader(
                symbol: symbol, companyName: companyName, metadata: companyMetadata,
                signal: range == .trades ? nil : signal, lastBar: chartData.bars.last, rates: currencyRates,
                currency: displayCurrency, hasTrades: !chartTrades.isEmpty,
                outsideTradeCount: outsideTradeCount,
                showingTrades: $showingTrades, range: rangeSelection,
                onImport: { Task { await loadImportedTrades() } }
            )
            if chartTrades.count < importedTrades.count {
                Text("Some imported trades could not be converted to \(displayCurrency).")
                    .font(.caption).foregroundStyle(.secondary)
            }
            cursorDetails
            if range.usesDailyBars ? isLoadingDaily : isLoading {
                ProgressView(range.usesDailyBars ? "Loading daily price history" : "Loading saved minute bars")
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
                                      : range.usesDailyBars ? "No daily prices are available for this symbol and period."
                                      : "Start a live feed to collect bars, or choose Latest to view older saved bars.")
                )
                .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                RadarChartPlot(
                    data: chartData, symbol: symbol,
                    displayCurrency: displayCurrency,
                    trades: showingTrades ? chartTrades : [],
                    priceHeight: max(140, availableHeight - 240),
                    volumeHeight: 60,
                    inspection: $cursorInspection
                )
                .id(displayCurrency)
                if let last = chartData.bars.last {
                    Text("\(chartData.bars.count) \(range.usesDailyBars ? "\(dailyProvider) daily" : "saved minute") bars · latest \(Date(timeIntervalSince1970: TimeInterval(last.minuteEpochSeconds)).formatted(.dateTime.month().day().hour().minute())) · chart in \(chartCurrency) · trading time · closed sessions compressed")
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

    @ViewBuilder
    private var cursorDetails: some View {
        if let cursorInspection {
            let bar = cursorInspection.bar
            let change = (bar.close / bar.open - 1) * 100
            let candleRange = (bar.high - bar.low) / bar.open * 100
            VStack(alignment: .leading, spacing: 2) {
                Text("\(Date(timeIntervalSince1970: TimeInterval(bar.minuteEpochSeconds)).formatted(.dateTime.day(.twoDigits).month(.twoDigits).year().hour().minute())) · \(direction(for: change)) \(signedPercent(change)) · Range \(candleRange.formatted(.number.precision(.fractionLength(2))))%")
                Text("O \(formattedPrice(bar.open))  H \(formattedPrice(bar.high))  L \(formattedPrice(bar.low))  C \(formattedPrice(bar.close))  ·  Volume \(compactVolume(bar.volume))  ·  \(cursorInspection.isPinned ? "PINNED" : "LIVE")")
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(TrendsColors.supportingInk)
            .accessibilityElement(children: .combine)
        } else {
            #if os(macOS)
            Label("Hover to inspect · click to pin", systemImage: "cursorarrow")
                .font(.caption).foregroundStyle(.secondary)
            #else
            Label("Drag to inspect · release to pin", systemImage: "hand.draw")
                .font(.caption).foregroundStyle(.secondary)
            #endif
        }
    }

    private func direction(for change: Double) -> String {
        change > 0 ? "UP" : change < 0 ? "DOWN" : "FLAT"
    }

    private func signedPercent(_ value: Double) -> String {
        "\(value > 0 ? "+" : "")\(value.formatted(.number.precision(.fractionLength(2))))%"
    }

    private func compactVolume(_ volume: Double) -> String {
        volume >= 1_000
            ? "\((volume / 1_000).formatted(.number.precision(.fractionLength(1))))k"
            : volume.formatted(.number.precision(.fractionLength(0)))
    }

    private func formattedPrice(_ value: Double) -> String {
        value.formatted(.currency(code: displayCurrency).precision(.fractionLength(2)))
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
            let trades = importedTrades
            let historyBounds = range == .trades ? tradeHistoryBounds : nil
            let loaded = try await Task.detached(priority: .userInitiated) {
                if yahooEnabled { await RadarTradeBarBackfill.shared.fill(symbol: requestedSymbol, trades: trades) }
                let store = try MarketBarStore(url: MarketBarStore.defaultURL())
                return try await store.loadRecentMinuteBars(
                    symbol: requestedSymbol,
                    fromEpochSeconds: historyBounds?.lowerBound ?? 0,
                    throughEpochSeconds: historyBounds?.upperBound ?? Int64(Date().timeIntervalSince1970),
                    limit: 2_000
                )
            }.value
            guard !Task.isCancelled else { return }
            allBars = loaded
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

    private func loadDailyBarsIfNeeded() async {
        guard range.usesDailyBars else { return }
        let requestedSymbol = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !requestedSymbol.isEmpty else { return }
        if dailySymbol == requestedSymbol, let dailyLoadedAt,
           Date().timeIntervalSince(dailyLoadedAt) < 15 * 60 { return }
        isLoadingDaily = true
        dailyError = nil
        do {
            guard yahooEnabled || fmpEnabled else { throw DailyHistoryError.unavailable }
            let loaded = try await RadarDailyHistoryService.shared.load(
                symbol: requestedSymbol, yahooEnabled: yahooEnabled, fmpEnabled: fmpEnabled
            )
            guard !Task.isCancelled else { return }
            dailyBars = loaded.bars
            dailyProvider = loaded.provider
            dailySymbol = requestedSymbol
            dailyLoadedAt = .now
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            dailyError = error.localizedDescription
            AppDiagnostics.shared.record(.warning, "RadarChart", "daily-history-failed",
                                         "symbol=\(requestedSymbol) error=\(String(describing: type(of: error)))")
        }
        isLoadingDaily = false
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
