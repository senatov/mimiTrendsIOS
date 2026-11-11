import SwiftUI

enum RadarActivity: Equatable {
    case loadingRankings(previousCount: Int?)

    var title: String {
        switch self {
        case .loadingRankings: "Collecting ranking candidates…"
        }
    }

    var detail: String {
        switch self {
        case .loadingRankings(let previousCount):
            if let previousCount { "\(previousCount) saved candidates remain available" }
            else { "Fetching the current market ranking" }
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
        let issues = progress.issues.joined(separator: " ")
        return "Updating market symbols. \(operation). Checked \(progress.processed) of \(progress.total). Successful \(progress.successful). Skipped \(progress.skipped): no recent minute bars \(progress.noRecentBars), no reported volume \(progress.noReportedVolume), unsupported symbols \(progress.unsupported). Errors \(progress.errors). \(lastBatch)\(issues) Saved signals remain available."
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
                    Text("Skipped: no recent minute bars \(progress.noRecentBars) · no reported volume \(progress.noReportedVolume) · unsupported symbols \(progress.unsupported)")
                        .font(.caption)
                        .foregroundStyle(TrendsColors.supportingInk)
                }
                ForEach(progress.issues, id: \.self) { issue in
                    Text(issue).font(.caption).foregroundStyle(.secondary)
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

    var body: some View {
        ZStack {
            Rectangle().fill(Color.black.opacity(colorScheme == .dark ? 0.28 : 0.08))
            VStack(alignment: .leading, spacing: 12) {
                Text("Restoring saved radar data…").font(.headline)
                Text("Loading signals from the previous session")
                    .font(.subheadline).foregroundStyle(TrendsColors.supportingInk)
                ProgressView().controlSize(.regular)
            }
            .frame(maxWidth: 360, alignment: .leading)
            .padding(20)
            .trendsPanel()
            .padding(12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Restoring saved radar data. Loading signals from the previous session.")
    }
}
