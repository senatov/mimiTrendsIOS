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

struct MarketScanProgressPanel: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let progress: MarketScanProgress

    private var operation: String {
        if !progress.activeSymbols.isEmpty {
            return "Checking \(progress.activeSymbols.joined(separator: ", "))"
        }
        return "Waiting for the next market batch"
    }

    private var accessibilitySummary: String {
        let lastBatch = progress.lastUpdatedAt.map {
            "Last batch completed \($0.formatted(date: .omitted, time: .shortened)). "
        } ?? ""
        return "Updating market symbols. \(operation). Checked \(progress.processed) of \(progress.total). Successful \(progress.successful). Skipped \(progress.skipped): no recent minute bars \(progress.noRecentBars), unsupported symbols \(progress.unsupported). Errors \(progress.errors). \(lastBatch)Saved signals remain available."
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "magnifyingglass")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.tint)
                .symbolEffect(.pulse, options: .repeating,
                              isActive: !reduceMotion && !progress.activeSymbols.isEmpty)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                Text("Updating market symbols")
                    .font(.headline)
                Text(operation)
                    .font(.subheadline)
                    .foregroundStyle(TrendsColors.supportingInk)
                ProgressView(value: Double(progress.processed), total: Double(max(progress.total, 1)))
                    .tint(.accentColor)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.45), value: progress.processed)
                    .accessibilityHidden(true)
                Text("Checked \(progress.processed) of \(progress.total)  ·  Successful \(progress.successful)  ·  Skipped \(progress.skipped)  ·  Errors \(progress.errors)")
                    .font(.subheadline.weight(.medium))
                if progress.skipped > 0 {
                    Text("Skipped: no recent minute bars \(progress.noRecentBars) · unsupported symbols \(progress.unsupported)")
                        .font(.caption)
                        .foregroundStyle(TrendsColors.supportingInk)
                }
                if let lastUpdatedAt = progress.lastUpdatedAt {
                    Text("Last batch completed \(lastUpdatedAt, format: .dateTime.hour().minute())")
                        .font(.caption)
                        .foregroundStyle(TrendsColors.supportingInk)
                }
                Text("Saved signals remain available while the scan continues.")
                    .font(.caption)
                    .foregroundStyle(TrendsColors.supportingInk)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .trendsPanel()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
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
        historyLoaded ? "Loading the first market sample…" : "Restoring saved radar data…"
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
