import SwiftUI
import UniformTypeIdentifiers

struct TradeImportSettingsSection: View {
    let width: CGFloat
    @State private var showingImporter = false
    @State private var isImporting = false
    @State private var report: BrokerImportReport?
    @State private var errorMessage: String?

    var body: some View {
        SettingsGroup(title: "Scalable trade history") {
            if width >= 700 {
                HStack(alignment: .center, spacing: 16) {
                    importDescription
                    Spacer(minLength: 8)
                    importButton
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    importDescription
                    importButton
                }
            }
        }
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

    private var importDescription: some View {
        HStack(alignment: .center, spacing: 16) {
            Image(systemName: "arrow.down.doc")
                .font(.title2.weight(.light))
                .foregroundStyle(.blue)
                .frame(width: 42, height: 42)
                .background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 4) {
                Text("Import transactions")
                    .font(.body.weight(.regular))
                Text("Choose a Scalable CSV export. The report lists added trades, cancelled rows, and duplicates.")
                    .font(.subheadline.weight(.light))
                    .foregroundStyle(TrendsColors.supportingInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var importButton: some View {
        TrendsActionButton(
            title: isImporting ? "Importing…" : "Choose CSV",
            systemImage: "square.and.arrow.down"
        ) {
            showingImporter = true
        }
        .disabled(isImporting)
    }

    private func importTrades(at url: URL) {
        isImporting = true
        Task {
            defer { isImporting = false }
            do {
                report = try await TradeImportCoordinator.importScalableCSV(at: url)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
