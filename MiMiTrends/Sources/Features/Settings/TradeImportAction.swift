import SwiftUI
import UniformTypeIdentifiers

struct TradeImportAction: View {
    let title: String
    var onImport: () -> Void = {}
    @State private var showingImporter = false
    @State private var isImporting = false
    @State private var report: BrokerImportReport?
    @State private var errorMessage: String?

    var body: some View {
        TrendsActionButton(
            title: isImporting ? "Importing…" : title,
            systemImage: "square.and.arrow.down"
        ) {
            showingImporter = true
        }
        .disabled(isImporting)
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.commaSeparatedText]) { result in
            switch result {
            case .success(let url): importTrades(at: url)
            case .failure(let error):
                if (error as? CocoaError)?.code != .userCancelled {
                    errorMessage = error.localizedDescription
                }
            }
        }
        .sheet(item: $report) { TradeImportReportView(report: $0) }
        .alert("Trade import failed", isPresented: errorIsPresented) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "The selected file could not be imported.")
        }
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    private func importTrades(at url: URL) {
        isImporting = true
        Task {
            defer { isImporting = false }
            do {
                report = try await TradeImportCoordinator.importScalableCSV(at: url)
                onImport()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
