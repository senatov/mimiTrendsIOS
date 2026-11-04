import SwiftUI

struct TradeImportReportView: View {
    let report: BrokerImportReport

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(report.fileName)
                        .font(.headline.weight(.regular))
                        .lineLimit(2)
                        .foregroundStyle(TrendsColors.supportingInk)
                    HStack(spacing: 14) {
                        totalCard(title: "Imported", count: report.importedCount, color: .green)
                        totalCard(title: "Ignored", count: report.ignoredCount, color: .orange)
                    }
                    SettingsGroup(title: "Import details") {
                        SettingsValueRow(title: "Rows read", value: report.inputRows.formatted())
                        SettingsValueRow(title: "Valid trades", value: report.transactionsInFile.formatted())
                        SettingsValueRow(title: "Cancelled", value: report.cancelledRows.formatted())
                        SettingsValueRow(title: "Duplicates in file", value: report.duplicatesInFile.formatted())
                        SettingsValueRow(title: "Already imported", value: report.duplicatesInDatabase.formatted())
                    }
                    SettingsGroup(title: "Imported trade types") {
                        if report.importedByType.isEmpty {
                            Text("No new trades were added.")
                                .font(.body.weight(.light))
                                .foregroundStyle(TrendsColors.supportingInk)
                        } else {
                            ForEach(report.importedByType.keys.sorted(), id: \.self) { type in
                                SettingsValueRow(
                                    title: type,
                                    value: (report.importedByType[type] ?? 0).formatted()
                                )
                            }
                        }
                    }
                    Text("Cancelled rows and duplicate trades were not added to the local trade history.")
                        .font(.body.weight(.light))
                        .foregroundStyle(TrendsColors.supportingInk)
                }
                .padding(24)
                .frame(maxWidth: 760, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .background(SettingsColors.background)
            .navigationTitle("Scalable import")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    TrendsActionButton(title: "Done", systemImage: "checkmark") { dismiss() }
                }
            }
        }
        .frame(minWidth: 420, minHeight: 420)
    }

    @Environment(\.dismiss) private var dismiss

    private func totalCard(title: String, count: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(count.formatted())
                .font(.system(.largeTitle, weight: .light).monospacedDigit())
                .foregroundStyle(color)
            Text(title).font(.body.weight(.regular))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(SettingsColors.group, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12).strokeBorder(.primary.opacity(0.09), lineWidth: 1)
        }
    }
}
