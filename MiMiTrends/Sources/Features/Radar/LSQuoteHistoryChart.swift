import SwiftUI
import Charts

struct LSQuoteHistoryChart: View {
    let symbol: String
    let companyName: String
    let refreshID: Int
    @State private var observations: [LSQuoteObservation] = []
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(companyName).font(.headline)
            Text("Lang & Schwarz · bid / ask in EUR · sampled quotes, volume unavailable")
                .font(.caption).foregroundStyle(.secondary)
            if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
            if observations.isEmpty {
                ContentUnavailableView("Collecting quote history", systemImage: "chart.xyaxis.line")
            } else {
                Chart(Array(observations.enumerated()), id: \.offset) { _, quote in
                    LineMark(x: .value("Time", Date(timeIntervalSince1970: Double(quote.observedAtMillis) / 1_000)),
                             y: .value("EUR", quote.bid), series: .value("Side", "Bid"))
                        .foregroundStyle(by: .value("Side", "Bid"))
                    LineMark(x: .value("Time", Date(timeIntervalSince1970: Double(quote.observedAtMillis) / 1_000)),
                             y: .value("EUR", quote.ask), series: .value("Side", "Ask"))
                        .foregroundStyle(by: .value("Side", "Ask"))
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .frame(minHeight: 180)
            }
        }
        .padding(12)
        .trendsPanel()
        .task(id: "\(symbol)|\(refreshID)") {
            do {
                let requestedSymbol = symbol
                observations = try await Task.detached(priority: .userInitiated) {
                    let store = try MarketQuoteStore(url: MarketQuoteStore.defaultURL())
                    let now = Int64(Date().timeIntervalSince1970 * 1_000)
                    return try await store.loadLS(sinceMillis: now - 30 * 60_000)
                        .filter { "LS:" + $0.instrumentID == requestedSymbol }
                }.value
                errorMessage = nil
            } catch {
                observations = []
                errorMessage = "Quote history could not be loaded."
            }
        }
    }
}
