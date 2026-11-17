import SwiftUI

struct RadarSourcePanel: View {
    @Environment(RadarTableColorStore.self) private var tableColors
    @Environment(\.colorScheme) private var colorScheme

    let lsStatus: LSCandidateStatus?
    let marketCycle: MarketRadarCycle?
    @AppStorage("radar.scannerCandidatesHeight.v1") private var savedCandidatesHeight = 200.0
    @State private var draggedCandidatesHeight: Double?
    @State private var candidatesDragStart: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Sources")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Divider()
                RadarSourceTable(sources: telemetrySources)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .foregroundStyle(tableColor(.sourceBodyText))
            .background(tableColor(.sourceTableFill), in: RoundedRectangle(cornerRadius: 10))
            .trendsPanel()
            if marketCycle != nil {
                RadarSplitHandle(
                    axis: .rows,
                    value: min(1, max(0, candidatesHeight / 600)),
                    onDrag: { delta in
                        if candidatesDragStart == nil { candidatesDragStart = savedCandidatesHeight }
                        draggedCandidatesHeight = min(600, max(110, (candidatesDragStart ?? savedCandidatesHeight) + Double(delta)))
                    },
                    onFinish: {
                        if let draggedCandidatesHeight { savedCandidatesHeight = draggedCandidatesHeight }
                        draggedCandidatesHeight = nil
                        candidatesDragStart = nil
                    },
                    onAdjust: { direction in
                        savedCandidatesHeight = min(600, max(110, savedCandidatesHeight + Double(direction * 30)))
                    }
                )
                .accessibilityLabel("Resize Sources and Scanner Candidates")
                RadarScannerDiagnostics(
                    candidates: marketCycle?.candidates ?? [],
                    progress: marketCycle?.progress,
                    listHeight: CGFloat(candidatesHeight)
                )
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var candidatesHeight: Double { draggedCandidatesHeight ?? savedCandidatesHeight }

    private var telemetrySources: [RadarTelemetrySource] {
        [
            RadarTelemetrySource(
                name: "TradingView candidates",
                status: marketStatus(marketCycle?.tradingView),
                statusColor: marketColor(marketCycle?.tradingView),
                dotColor: marketColor(marketCycle?.tradingView),
                received: marketCycle?.tradingView.received,
                valid: marketCycle?.candidates.count,
                requests: marketCycle?.tradingView.operations,
                errors: marketCycle?.tradingView.errors,
                errorDetails: marketCycle?.tradingView.lastErrorMessage
            ),
            RadarTelemetrySource(
                name: "Yahoo candles",
                status: yahooStatus,
                statusColor: yahooColor, dotColor: yahooColor,
                received: marketCycle?.progress.processed,
                valid: marketCycle?.progress.successful,
                requests: marketCycle?.progress.processed,
                errors: marketCycle?.progress.errors,
                errorDetails: marketCycle?.progress.issues.joined(separator: "\n")
            ),
            RadarTelemetrySource(
                name: "Lang & Schwarz",
                status: lsStatus == nil ? "CONNECTING" : lsFreshCount > 0 ? "EUR QUOTES" : "NO FRESH QUOTES",
                statusColor: lsFreshCount > 0 ? tableColor(.sourceActive) : tableColor(.sourceInactive),
                dotColor: lsFreshCount > 0 ? tableColor(.sourceActive) : tableColor(.sourceInactive),
                received: lsStatus?.quotes.count, valid: lsStatus.map { _ in lsFreshCount },
                requests: lsStatus?.requestCount, errors: lsStatus?.errorCount
            )
        ]
    }

    private var yahooStatus: String {
        if let until = marketCycle?.yahooCooldownUntil, Date() < until { return "RATE LIMITED" }
        guard let marketCycle else { return "CONNECTING" }
        return marketCycle.progress.successful > 0 ? "ONLINE" : "WAITING"
    }

    private var yahooColor: Color {
        yahooStatus == "RATE LIMITED" ? tableColor(.sourceAttention) :
            (yahooStatus == "ONLINE" ? tableColor(.sourceActive) : tableColor(.sourceInactive))
    }

    private func tableColor(_ role: RadarTableColorRole) -> Color {
        tableColors.color(role, dark: colorScheme == .dark)
    }

    private func marketStatus(_ totals: RadarSourceTotals?) -> String {
        guard let totals else { return "CONNECTING" }
        if totals.errors > 0, totals.valid == 0 { return "ATTENTION" }
        return totals.valid > 0 ? "ONLINE" : "WAITING"
    }

    private func marketColor(_ totals: RadarSourceTotals?) -> Color {
        guard let totals else { return tableColor(.sourceInactive) }
        if totals.errors > 0, totals.valid == 0 { return tableColor(.sourceAttention) }
        return totals.valid > 0 ? tableColor(.sourceActive) : tableColor(.sourceInactive)
    }

    private var lsFreshCount: Int {
        lsStatus?.freshCount(atMillis: Int64(Date().timeIntervalSince1970 * 1_000)) ?? 0
    }

}
