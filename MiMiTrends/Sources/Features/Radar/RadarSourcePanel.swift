import SwiftUI

struct RadarSourcePanel: View {
    @Environment(RadarTableColorStore.self) private var tableColors
    @Environment(\.colorScheme) private var colorScheme

    let session: RadarSession
    let discoveryStatus: DiscoveryRefreshStatus?
    let lsStatus: LSCandidateStatus?
    let discoveryRequests: Int
    let discoveryErrors: Int
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
            if let snapshot = discoveryStatus?.snapshot {
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
                    snapshot: snapshot, progress: marketCycle?.progress,
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
                name: "Yahoo history", status: yahooStatus,
                statusColor: yahooColor, dotColor: yahooColor,
                received: marketCycle?.yahoo.received, valid: marketCycle?.yahoo.valid,
                requests: marketCycle?.yahoo.operations, errors: marketCycle?.yahoo.errors,
                errorDetails: marketCycle?.yahoo.lastErrorMessage
            ),
            RadarTelemetrySource(
                name: "Finnhub", status: feedStatus, statusColor: feedColor, dotColor: feedColor,
                received: session.tradeCount, valid: session.completedBarsStored,
                requests: nil, errors: session.errorCount,
                errorDetails: session.errorMessage
            ),
            RadarTelemetrySource(
                name: "Lang & Schwarz",
                status: lsStatus == nil ? "CONNECTING" : lsFreshCount > 0 ? "EUR QUOTES" : "NO FRESH QUOTES",
                statusColor: lsFreshCount > 0 ? tableColor(.sourceActive) : tableColor(.sourceInactive),
                dotColor: lsFreshCount > 0 ? tableColor(.sourceActive) : tableColor(.sourceInactive),
                received: lsStatus?.quotes.count, valid: lsStatus.map { _ in lsFreshCount },
                requests: lsStatus?.requestCount, errors: lsStatus?.errorCount
            ),
            RadarTelemetrySource(
                name: "wallstreetONLINE", status: discoveryLabel,
                statusColor: discoveryColor, dotColor: discoveryColor,
                received: discoveryStatus?.snapshot?.candidates.count, valid: nil,
                requests: discoveryRequests, errors: discoveryErrors
            ),
            RadarTelemetrySource(
                name: marketCycle?.usesFMP == true ? "FMP" : "TraderFox",
                status: marketStatus(candidateTotals),
                statusColor: marketColor(candidateTotals), dotColor: marketColor(candidateTotals),
                received: candidateTotals?.received, valid: candidateTotals?.valid,
                requests: candidateTotals?.operations, errors: candidateTotals?.errors,
                errorDetails: candidateTotals?.lastErrorMessage
            )
        ] + (discoveryStatus?.rankingSources ?? []).map { source in
            let color = tableColor(source.failed ? .sourceAttention : source.enabled ? .sourceActive : .sourceInactive)
            return RadarTelemetrySource(
                name: source.kind == .wikifolio ? "wO Wikifolio" : "wO Performance",
                status: !source.enabled ? "DISABLED" : source.failed ? "REFRESH FAILED" : source.lastSuccess == nil ? "CONNECTING" : "TODAY · RANKING",
                statusColor: color, dotColor: color,
                received: source.count, valid: source.enabled && !source.failed ? source.count : nil,
                requests: nil, errors: source.failed ? 1 : 0
            )
        }
    }

    private var candidateTotals: RadarSourceTotals? {
        guard let marketCycle else { return nil }
        return marketCycle.usesFMP ? marketCycle.fmp : marketCycle.traderFox
    }

    private var yahooStatus: String {
        if let until = marketCycle?.yahooCooldownUntil, Date() < until { return "RATE LIMITED" }
        return marketStatus(marketCycle?.yahoo)
    }

    private var yahooColor: Color {
        yahooStatus == "RATE LIMITED" ? tableColor(.sourceAttention) : marketColor(marketCycle?.yahoo)
    }

    private func tableColor(_ role: RadarTableColorRole) -> Color {
        tableColors.color(role, dark: colorScheme == .dark)
    }

    private var discoveryLabel: String {
        guard let discoveryStatus else { return "CONNECTING" }
        if discoveryStatus.hasFreshSnapshot(atMillis: Int64(Date().timeIntervalSince1970 * 1_000)) {
            return "SHARED SCAN POOL"
        }
        return discoveryStatus.isAvailable ? "SAVED" : "UNAVAILABLE"
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

    private var discoveryColor: Color {
        discoveryLabel == "SHARED SCAN POOL" ? tableColor(.sourceActive) : tableColor(.sourceInactive)
    }

    private var lsFreshCount: Int {
        lsStatus?.freshCount(atMillis: Int64(Date().timeIntervalSince1970 * 1_000)) ?? 0
    }

    private var feedStatus: String {
        if session.isSubscribed { return session.tradeCount > 0 ? "RECEIVING" : "WAITING" }
        if session.isScanning { return "CONNECTING" }
        if session.errorMessage != nil { return "ATTENTION" }
        return "STOPPED"
    }

    private var feedColor: Color {
        if session.isSubscribed { return tableColor(.sourceActive) }
        if session.errorMessage != nil { return tableColor(.sourceAttention) }
        return tableColor(.sourceInactive)
    }

}
