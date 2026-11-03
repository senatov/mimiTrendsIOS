import SwiftUI

enum RadarActivity: Equatable {
    case loadingRankings(previousCount: Int?)
    case preparingFeed
    case connectingFeed(symbolCount: Int)

    var title: String {
        switch self {
        case .loadingRankings: "Collecting ranking candidates…"
        case .preparingFeed: "Preparing live feed…"
        case .connectingFeed: "Connecting to Finnhub…"
        }
    }

    var detail: String {
        switch self {
        case .loadingRankings(let previousCount):
            if let previousCount { "\(previousCount) saved candidates remain available" }
            else { "Fetching the current market ranking" }
        case .preparingFeed:
            "Loading the selected symbols and scan settings"
        case .connectingFeed(let symbolCount):
            "Requesting live trades for \(symbolCount) \(symbolCount == 1 ? "symbol" : "symbols")"
        }
    }
}

struct RadarActivityBanner: View {
    let activity: RadarActivity

    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
                .controlSize(.regular)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(activity.title)
                    .font(.subheadline.weight(.regular))
                Text(activity.detail)
                    .font(.subheadline.weight(.light))
                    .foregroundStyle(TrendsColors.supportingInk)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .trendsPanel()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(activity.title) \(activity.detail)")
    }
}

struct RadarWarmupOverlay: View {
    @Environment(\.colorScheme) private var colorScheme
    let historyLoaded: Bool
    let savedCount: Int
    let processed: Int
    let total: Int

    private var title: String {
        historyLoaded ? "Collecting current market statistics…" : "Restoring saved radar data…"
    }

    private var detail: String {
        if !historyLoaded { return "Loading signals from the previous session" }
        if total == 0 { return "Finding market candidates" }
        return "Checked \(min(processed, total)) of \(total) market symbols"
    }

    var body: some View {
        ZStack {
            Rectangle().fill(Color.black.opacity(colorScheme == .dark ? 0.28 : 0.08))
            VStack(alignment: .leading, spacing: 12) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(TrendsColors.supportingInk)
                if historyLoaded && total > 0 {
                    ProgressView(value: Double(min(processed, total)), total: Double(total))
                } else {
                    ProgressView().controlSize(.regular)
                }
                if savedCount > 0 {
                    Text("\(savedCount) saved signals loaded")
                        .font(.caption).foregroundStyle(TrendsColors.supportingInk)
                }
            }
            .frame(maxWidth: 360, alignment: .leading)
            .padding(20)
            .trendsPanel()
            .padding(12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) \(detail)")
    }
}
