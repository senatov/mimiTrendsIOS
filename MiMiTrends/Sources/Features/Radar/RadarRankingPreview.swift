import SwiftUI

struct RadarRankingPreview: View {
    let snapshot: DiscoverySnapshot

    private var leaders: [DiscoveryCandidate] {
        Array(snapshot.candidates
            .filter { $0.origin?.period == .day && $0.marketMetrics != nil }
            .sorted { $0.rank < $1.rank }
            .prefix(10))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Published market ranking · 1 day")
                    .font(.subheadline.weight(.regular))
                Spacer(minLength: 8)
                NavigationLink("All \(snapshot.candidates.count)") {
                    DiscoveryCandidateList(snapshot: snapshot)
                }
                .buttonStyle(TrendsActionButtonStyle(compact: true))
            }
            Text("miminavi.tech · updated \(Date(timeIntervalSince1970: TimeInterval(snapshot.refreshedAtMillis) / 1_000), style: .relative) · ranking data, not scanner signals")
                .font(.caption)
                .foregroundStyle(TrendsColors.supportingInk)
            ForEach(leaders, id: \.identity) { candidate in
                if let metrics = candidate.marketMetrics {
                    HStack(spacing: 8) {
                        Text("#\(candidate.rank)")
                            .frame(width: 30, alignment: .leading)
                            .foregroundStyle(TrendsColors.supportingInk)
                        Text(candidate.displayName ?? candidate.instrumentID)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(String(format: "%+.2f%%", metrics.change1dPercent))
                            .monospacedDigit()
                            .foregroundStyle(metrics.change1dPercent < 0 ? .red : .green)
                            .frame(width: 75, alignment: .trailing)
                    }
                    .font(.caption)
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
