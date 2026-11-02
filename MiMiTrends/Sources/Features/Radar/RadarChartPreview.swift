import SwiftUI
import UniformTypeIdentifiers

struct RadarChartPreview: View {
    let symbol: String
    let signal: ScanResult?
    let refreshID: Int
    let onImportSymbol: (String) -> Void

    @State private var allBars: [MinuteBar] = []
    @AppStorage("chart.range.v1") private var rangeRaw = RadarChartRange.oneDay.rawValue
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var isImporting = false
    @State private var showingImporter = false
    @State private var importMessage: String?

    private var chartData: RadarChartData {
        RadarChartData(
            allBars: allBars, range: range,
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
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [UTType(filenameExtension: "sqlite") ?? .data]
        ) { result in
            switch result {
            case .success(let url):
                Task { await importSnapshot(at: url) }
            case .failure(let error):
                importMessage = error.localizedDescription
            }
        }
    }

    private func chartContent(availableHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Selected alert chart").font(.headline.weight(.regular))
                Spacer()
                TrendsActionButton(
                    title: "Import desktop snapshot",
                    systemImage: "square.and.arrow.down",
                    tint: .teal
                ) { showingImporter = true }
                .disabled(isImporting)
                if let signal {
                    Text(signal.signalSource.replacingOccurrences(of: "_", with: " "))
                        .font(.caption.weight(.regular))
                        .foregroundStyle(signal.windowChangePercent < 0 ? .red : .green)
                }
            }
            Divider()
            if isImporting { ProgressView("Importing minute bars") }
            if let importMessage {
                Text(importMessage).font(.footnote).foregroundStyle(.secondary)
            }
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
                    Text(signal.price.formatted(.number.precision(.fractionLength(0...2))))
                        .font(.title3.monospacedDigit())
                    Text("\(signal.windowChangePercent.formatted(.number.precision(.fractionLength(2))))%")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(signal.windowChangePercent < 0 ? .red : .green)
                } else if let last = chartData.bars.last {
                    Text(last.close.formatted(.number.precision(.fractionLength(2))))
                        .font(.title3.monospacedDigit())
                    Text("latest saved close")
                        .font(.subheadline.weight(.light))
                        .foregroundStyle(TrendsColors.supportingInk)
                }
            }
            if isLoading {
                ProgressView("Loading saved minute bars")
                    .frame(maxWidth: .infinity, minHeight: 180)
            } else if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
                    .frame(maxWidth: .infinity, minHeight: 180)
            } else if chartData.bars.isEmpty {
                ContentUnavailableView(
                    "No saved bars in \(range.title)",
                    systemImage: "chart.xyaxis.line",
                    description: Text("Start a live feed, import a desktop snapshot here, or choose Latest for older saved bars.")
                )
                .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                RadarChartPlot(
                    data: chartData, symbol: symbol,
                    priceHeight: max(140, availableHeight - 240),
                    volumeHeight: 60
                )
                if let last = chartData.bars.last {
                    Text("\(chartData.bars.count) saved bars · latest \(Date(timeIntervalSince1970: TimeInterval(last.minuteEpochSeconds)).formatted(.dateTime.month().day().hour().minute())) · source currency · gaps are not filled")
                        .font(.subheadline.weight(.light))
                        .foregroundStyle(TrendsColors.supportingInk)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

    private func importSnapshot(at url: URL) async {
        isImporting = true
        importMessage = nil
        do {
            let summary = try await DesktopBarSnapshotImporter.importSnapshot(
                at: url, into: MarketBarStore.defaultURL()
            )
            rangeRaw = RadarChartRange.latest.rawValue
            onImportSymbol(summary.symbol)
            importMessage = "Imported \(summary.barCount) bars for \(summary.symbol); \(summary.changedCount) saved or updated."
        } catch {
            importMessage = error.localizedDescription
        }
        isImporting = false
    }

}
