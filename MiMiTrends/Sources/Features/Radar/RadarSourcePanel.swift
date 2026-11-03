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

    @State private var showingCandidates = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Source telemetry")
                .font(.title3.weight(.light))
            Divider()
            GeometryReader { geometry in
                telemetryTable(availableWidth: geometry.size.width)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .foregroundStyle(tableColor(.sourceBodyText))
        .background(tableColor(.sourceTableFill), in: RoundedRectangle(cornerRadius: 10))
        .trendsPanel()
        .navigationDestination(isPresented: $showingCandidates) {
            if let snapshot = discoveryStatus?.snapshot {
                DiscoveryCandidateList(snapshot: snapshot)
            }
        }
    }

    private func telemetryTable(availableWidth: CGFloat) -> some View {
        RadarSourceTable(
            sources: telemetrySources,
            availableWidth: availableWidth,
            onShowCandidates: { showingCandidates = true }
        )
    }

    private var telemetrySources: [RadarTelemetrySource] {
        var rows = [
            RadarTelemetrySource(
                name: "Yahoo", status: marketStatus(marketCycle?.yahoo),
                statusColor: marketColor(marketCycle?.yahoo), dotColor: marketColor(marketCycle?.yahoo),
                received: marketCycle?.yahoo.received, valid: marketCycle?.yahoo.valid,
                requests: marketCycle?.yahoo.operations, errors: marketCycle?.yahoo.errors,
                canShowCandidates: false
            ),
            RadarTelemetrySource(
                name: "Finnhub", status: feedStatus, statusColor: feedColor, dotColor: feedColor,
                received: session.tradeCount, valid: session.completedBarsStored,
                requests: nil, errors: session.errorCount,
                canShowCandidates: false
            ),
            RadarTelemetrySource(
                name: "Lang & Schwarz",
                status: lsStatus == nil ? "CONNECTING" : lsFreshCount > 0 ? "EUR QUOTES" : "NO FRESH QUOTES",
                statusColor: lsFreshCount > 0 ? tableColor(.sourceActive) : tableColor(.sourceInactive),
                dotColor: lsFreshCount > 0 ? tableColor(.sourceActive) : tableColor(.sourceInactive),
                received: lsStatus?.quotes.count, valid: lsStatus.map { _ in lsFreshCount },
                requests: lsStatus?.requestCount, errors: lsStatus?.errorCount,
                canShowCandidates: false
            ),
            RadarTelemetrySource(
                name: "wallstreetONLINE", status: discoveryLabel,
                statusColor: discoveryColor, dotColor: discoveryColor,
                received: discoveryStatus?.snapshot?.candidates.count, valid: nil,
                requests: discoveryRequests, errors: discoveryErrors,
                canShowCandidates: discoveryStatus?.snapshot != nil
            ),
            RadarTelemetrySource(
                name: "TraderFox", status: marketStatus(marketCycle?.traderFox),
                statusColor: marketColor(marketCycle?.traderFox), dotColor: marketColor(marketCycle?.traderFox),
                received: marketCycle?.traderFox.received, valid: marketCycle?.traderFox.valid,
                requests: marketCycle?.traderFox.operations, errors: marketCycle?.traderFox.errors,
                canShowCandidates: false
            )
        ]
        rows.insert(
            RadarTelemetrySource(
                name: "Scalable", status: "NO CONNECTION",
                statusColor: tableColor(.sourceInactive), dotColor: tableColor(.sourceInactive),
                received: nil, valid: nil, requests: nil, errors: nil,
                canShowCandidates: false
            ),
            at: 2
        )
        return rows
    }

    private func tableColor(_ role: RadarTableColorRole) -> Color {
        tableColors.color(role, dark: colorScheme == .dark)
    }

    private var discoveryLabel: String {
        guard let discoveryStatus else { return "CONNECTING" }
        if discoveryStatus.hasFreshSnapshot(atMillis: Int64(Date().timeIntervalSince1970 * 1_000)) {
            return "RANKING + LINKS"
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
        discoveryLabel == "RANKING + LINKS" ? tableColor(.sourceActive) : tableColor(.sourceInactive)
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
