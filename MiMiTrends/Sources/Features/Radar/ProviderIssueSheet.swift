import SwiftUI

struct ProviderIssueSheet: View {
    let issue: MarketProviderPreflightIssue
    let openProviderSettings: () -> Void
    let disableProvider: () -> Void
    let retry: () -> Void
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("\(issue.provider.title) needs attention", systemImage: "exclamationmark.triangle.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.red)
            Text(issue.reason)
                .font(.body)
            HStack {
                if let url = issue.provider.accountURL {
                    TrendsActionButton(title: "Open provider", systemImage: "arrow.up.right") {
                        openURL(url)
                    }
                }
                TrendsActionButton(title: "Provider settings", systemImage: "gearshape") {
                    openProviderSettings()
                }
            }
            HStack {
                TrendsActionButton(title: "Disable provider", systemImage: "xmark.circle", tint: .red) {
                    disableProvider()
                }
                Spacer()
                TrendsActionButton(title: "Check again", systemImage: "arrow.clockwise") {
                    retry()
                }
            }
        }
        .padding(24)
        .frame(minWidth: 380, maxWidth: 520)
        .background(.background)
    }
}
