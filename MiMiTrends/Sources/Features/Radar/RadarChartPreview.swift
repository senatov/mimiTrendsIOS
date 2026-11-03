import SwiftUI

struct RadarChartPreview: View {
    let symbol: String
    let companyName: String
    let signal: ScanResult?
    let exchangeRate: FMPExchangeRate?
    let refreshID: Int

    @State private var allBars: [MinuteBar] = []
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
            allBars: range.usesDailyBars ? (dailySymbol == symbol ? dailyBars : []) : allBars,
            range: range,
            nowEpochSeconds: Int64(Date().timeIntervalSince1970)
        )
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
            }
        }
        .trendsPanel()
        .task(id: "\(symbol)|\(refreshID)") { await loadBars() }
        .task(id: "daily|\(symbol)|\(range.rawValue)") { await loadDailyBarsIfNeeded() }
        .task(id: "trades|\(symbol)|\(companyName)") { await loadImportedTrades() }
    }

    private func chartContent(availableHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Selected alert chart").font(.headline.weight(.regular))
                Spacer()
                if !chartTrades.isEmpty {
                    Toggle("Trades", isOn: $showingTrades)
                        .toggleStyle(.button)
                        .help("Show imported trades on the chart")
                }
                TradeImportAction(title: "Import trades") {
                    Task { await loadImportedTrades() }
                }
                if let signal {
                    Text(signal.signalSource.replacingOccurrences(of: "_", with: " "))
                        .font(.caption.weight(.regular))
                        .foregroundStyle(signal.windowChangePercent < 0 ? .red : .green)
                }
            }
        if chartTrades.count < importedTrades.count {
            Text("Imported trades in another currency are hidden from this chart.")
                .font(.caption)
                .foregroundStyle(TrendsColors.supportingInk)
        }
            Divider()
            HStack {
                Picker("Range", selection: rangeSelection) {
                    ForEach(RadarChartRange.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 350)
                Spacer(minLength: 0)
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(symbol.isEmpty ? "No symbol selected" : symbol)
                    .font(.title3.weight(.regular))
                if let signal {
                    let price = RadarSignalPrice.display(signal, exchangeRate: exchangeRate,
                                                         nowMillis: Int64(Date().timeIntervalSince1970 * 1_000))
                    Text(price.text)
                        .font(.title3.monospacedDigit())
                        .help(price.explanation)
                    Text("\(signal.windowChangePercent.formatted(.number.precision(.fractionLength(2))))%")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(signal.windowChangePercent < 0 ? .red : .green)
                } else if let last = chartData.bars.last {
                    Text(formattedPrice(last.close))
                        .font(.title3.monospacedDigit())
                    Text("latest saved close")
                        .font(.subheadline.weight(.light))
                        .foregroundStyle(TrendsColors.supportingInk)
                }
            }
            cursorDetails
            if range.usesDailyBars ? isLoadingDaily : isLoading {
                ProgressView(range.usesDailyBars ? "Loading FMP daily prices" : "Loading saved minute bars")
                    .frame(maxWidth: .infinity, minHeight: 180)
            } else if let message = range.usesDailyBars ? dailyError : errorMessage {
                Text(message).foregroundStyle(.red)
                    .frame(maxWidth: .infinity, minHeight: 180)
            } else if chartData.bars.isEmpty {
                ContentUnavailableView(
                    "No prices in \(range.title)",
                    systemImage: "chart.xyaxis.line",
                    description: Text(range.usesDailyBars
                                      ? "FMP has no daily prices for this symbol and period."
                                      : "Start a live feed to collect bars, or choose Latest to view older saved bars.")
                )
                .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                RadarChartPlot(
                    data: chartData, symbol: symbol,
                    trades: showingTrades ? chartTrades : [],
                    priceHeight: max(140, availableHeight - 240),
                    volumeHeight: 60,
                    inspection: $cursorInspection
                )
                if let last = chartData.bars.last {
                    Text("\(chartData.bars.count) \(range.usesDailyBars ? "FMP daily" : "saved minute") bars · latest \(Date(timeIntervalSince1970: TimeInterval(last.minuteEpochSeconds)).formatted(.dateTime.month().day().hour().minute())) · chart in \(chartCurrency) · gaps are not filled")
                        .font(.subheadline.weight(.light))
                        .foregroundStyle(TrendsColors.supportingInk)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var chartTrades: [BrokerTradePosition] {
        importedTrades.filter { $0.currency.caseInsensitiveCompare(chartCurrency) == .orderedSame }
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
            Text("Move cursor or drag over a candle · click to pin")
                .font(.caption)
                .foregroundStyle(TrendsColors.supportingInk)
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
        value.formatted(.currency(code: chartCurrency).precision(.fractionLength(2)))
    }

    private var chartCurrency: String {
        [".DE", ".F", ".PA", ".AS", ".MI", ".HE"].contains(where: symbol.hasSuffix) ? "EUR" : "USD"
    }

    private func loadBars() async {
        let requestedSymbol = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !requestedSymbol.isEmpty else {
            allBars = []
            return
        }
        isLoading = true
        errorMessage = nil
        do {
            let loaded = try await Task.detached(priority: .userInitiated) {
                let store = try MarketBarStore(url: MarketBarStore.defaultURL())
                return try await store.loadRecentMinuteBars(
                    symbol: requestedSymbol,
                    fromEpochSeconds: 0,
                    throughEpochSeconds: Int64(Date().timeIntervalSince1970),
                    limit: 360
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
        guard let apiKey = try? ProviderCredentialStore.load(FMPCredential.account) else {
            dailyError = "Add a Financial Modeling Prep API key in Settings to load 1W and 1Y prices."
            return
        }
        isLoadingDaily = true
        dailyError = nil
        do {
            let loaded = try await FMPHistoricalPriceSource().dailyBars(symbol: requestedSymbol, apiKey: apiKey)
            guard !Task.isCancelled else { return }
            dailyBars = loaded
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
