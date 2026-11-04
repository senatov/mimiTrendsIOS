import SwiftUI

struct RadarCoverageView: View {
    @Environment(\.dismiss) private var dismiss
    let request: RadarCoverageRequest
    @State private var result: CoverageResult?

    private let client = RecentCoverageClient()

    var body: some View {
        NavigationStack {
            Group {
                if let result {
                    coverageList(result)
                } else {
                    ProgressView("Loading recent messages…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("Rumors · \(request.symbol)")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    TrendsActionButton(title: "Done", systemImage: "checkmark") { dismiss() }
                }
            }
        }
        .task(id: request.id) {
            result = await client.load(symbol: request.symbol, companyName: request.companyName)
        }
        #if os(iOS)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        #endif
    }

    @ViewBuilder
    private func coverageList(_ result: CoverageResult) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                Text(request.companyName)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                if let url = ReutersSearch.url(symbol: request.symbol) {
                    Link(destination: url) {
                        Label("Reuters · \(request.symbol)", systemImage: "newspaper")
                    }
                    .buttonStyle(TrendsActionButtonStyle(compact: true))
                    Text("Open the full Reuters search for \(request.symbol).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("News published in the last 10 hours · newest first")
                    .font(.subheadline.weight(.medium))
                if result.items.isEmpty {
                    ContentUnavailableView(
                        result.unavailableSources.count == 4 ? "News sources unavailable" : "No news in the last 10 hours",
                        systemImage: result.unavailableSources.count == 4 ? "wifi.slash" : "newspaper",
                        description: Text(result.unavailableSources.count == 4
                                          ? "Try again later." : "No dated news was found for this stock in the last 10 hours.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 180)
                } else {
                    ForEach(result.items) { item in
                        coverageItem(item)
                    }
                }
                if !result.unavailableSources.isEmpty {
                    Text("Unavailable: \(result.unavailableSources.joined(separator: ", "))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
        }
    }

    private func coverageItem(_ item: CoverageItem) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Divider()
            Link(destination: item.url) {
                Text(item.title)
                    .font(.body)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 6) {
                Text(item.publisher)
                if let date = item.publishedAt {
                    Text("·")
                    Text(date, format: .dateTime.day().month(.abbreviated).year().hour().minute())
                } else if let label = item.publishedLabel {
                    Text("·")
                    Text(label)
                } else {
                    Text("·")
                    Text("Time unknown")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}
