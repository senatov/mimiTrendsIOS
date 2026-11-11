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
                    ProgressView("Loading news…")
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
                Text("News for \(request.symbol) · newest first")
                    .font(.subheadline.weight(.medium))
                if result.items.isEmpty {
                    ContentUnavailableView(
                        result.unavailableSources.count == 3 ? "News sources unavailable" : "No news found",
                        systemImage: result.unavailableSources.count == 3 ? "wifi.slash" : "newspaper",
                        description: Text(result.unavailableSources.count == 3
                                          ? "Try again later." : "No news was found for this stock.")
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
