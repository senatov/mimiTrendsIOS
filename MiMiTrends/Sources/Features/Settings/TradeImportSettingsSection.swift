import SwiftUI

struct TradeImportSettingsSection: View {
    let width: CGFloat

    var body: some View {
        SettingsGroup(title: "Trade history") {
            if width >= 700 {
                HStack(alignment: .center, spacing: 16) {
                    importDescription
                    Spacer(minLength: 8)
                    TradeImportAction(title: "Choose CSV")
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    importDescription
                    TradeImportAction(title: "Choose CSV")
                }
            }
        }
    }

    private var importDescription: some View {
        HStack(alignment: .center, spacing: 16) {
            Image(systemName: "arrow.down.doc.fill")
                .font(.title2.weight(.semibold))
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

}
