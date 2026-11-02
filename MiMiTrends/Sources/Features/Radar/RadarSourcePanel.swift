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

    #if os(macOS)
    @State private var scalableStatus = "CHECKING"
    @State private var scalableChecks = 0
    @State private var scalableErrors = 0
    @State private var loginTask: Task<Void, Never>?
    #endif
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
        .foregroundStyle(tableColor(.bodyText))
        .trendsPanel()
        .navigationDestination(isPresented: $showingCandidates) {
            if let snapshot = discoveryStatus?.snapshot {
                DiscoveryCandidateList(snapshot: snapshot)
            }
        }
        #if os(macOS)
        .task { await checkScalable() }
        .onDisappear { loginTask?.cancel() }
        #endif
    }

    private func telemetryTable(availableWidth: CGFloat) -> some View {
        RadarSourceTable(
            sources: telemetrySources,
            availableWidth: availableWidth,
            onLogin: loginAction,
            onShowCandidates: { showingCandidates = true }
        )
    }

    private var loginAction: () -> Void {
        #if os(macOS)
        { startScalableLogin() }
        #else
        {}
        #endif
    }

    private var telemetrySources: [RadarTelemetrySource] {
        var rows = [
            RadarTelemetrySource(
                name: "Yahoo", status: marketStatus(marketCycle?.yahoo),
                statusColor: marketColor(marketCycle?.yahoo), dotColor: marketColor(marketCycle?.yahoo),
                received: marketCycle?.yahoo.received, valid: marketCycle?.yahoo.valid,
                requests: marketCycle?.yahoo.operations, errors: marketCycle?.yahoo.errors,
                canLogin: false, canShowCandidates: false
            ),
            RadarTelemetrySource(
                name: "Finnhub", status: feedStatus, statusColor: feedColor, dotColor: feedColor,
                received: session.tradeCount, valid: session.completedBarsStored,
                requests: nil, errors: session.errorCount,
                canLogin: false, canShowCandidates: false
            ),
            RadarTelemetrySource(
                name: "Lang & Schwarz",
                status: lsStatus == nil ? "CONNECTING" : lsFreshCount > 0 ? "EUR QUOTES" : "NO FRESH QUOTES",
                statusColor: lsFreshCount > 0 ? tableColor(.sourceActive) : tableColor(.sourceInactive),
                dotColor: lsFreshCount > 0 ? tableColor(.sourceActive) : tableColor(.sourceInactive),
                received: lsStatus?.quotes.count, valid: lsStatus.map { _ in lsFreshCount },
                requests: lsStatus?.requestCount, errors: lsStatus?.errorCount,
                canLogin: false, canShowCandidates: false
            ),
            RadarTelemetrySource(
                name: "wallstreetONLINE", status: discoveryLabel,
                statusColor: discoveryColor, dotColor: discoveryColor,
                received: discoveryStatus?.snapshot?.candidates.count, valid: nil,
                requests: discoveryRequests, errors: discoveryErrors,
                canLogin: false, canShowCandidates: discoveryStatus?.snapshot != nil
            ),
            RadarTelemetrySource(
                name: "TraderFox", status: marketStatus(marketCycle?.traderFox),
                statusColor: marketColor(marketCycle?.traderFox), dotColor: marketColor(marketCycle?.traderFox),
                received: marketCycle?.traderFox.received, valid: marketCycle?.traderFox.valid,
                requests: marketCycle?.traderFox.operations, errors: marketCycle?.traderFox.errors,
                canLogin: false, canShowCandidates: false
            )
        ]
        #if os(macOS)
        rows.insert(
            RadarTelemetrySource(
                name: "Scalable", status: scalableStatus,
                statusColor: tableColor(scalableStatus == "LOGIN NEEDED" ? .sourceAttention : .sourceInactive),
                dotColor: tableColor(scalableStatus == "LOGIN NEEDED" ? .sourceAttention : .sourceInactive),
                received: nil, valid: nil, requests: scalableChecks, errors: scalableErrors,
                canLogin: scalableStatus == "LOGIN NEEDED", canShowCandidates: false
            ),
            at: 2
        )
        #else
        rows.insert(
            RadarTelemetrySource(
                name: "Scalable", status: "NOT CONNECTED",
                statusColor: tableColor(.sourceInactive), dotColor: tableColor(.sourceInactive),
                received: nil, valid: nil, requests: nil, errors: nil,
                canLogin: false, canShowCandidates: false
            ),
            at: 2
        )
        #endif
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

    #if os(macOS)
    private func checkScalable() async {
        scalableChecks += 1
        do {
            scalableStatus = try await ScalableCLIService().isAuthorized() ? "CLI READY" : "LOGIN NEEDED"
        } catch ScalableCLIError.notInstalled {
            scalableStatus = "CLI UNAVAILABLE"
            scalableErrors += 1
        } catch {
            scalableStatus = "LOGIN NEEDED"
            scalableErrors += 1
        }
    }

    private func startScalableLogin() {
        guard loginTask == nil else { return }
        scalableStatus = "SIGNING IN"
        loginTask = Task {
            do {
                try await ScalableCLIService().startReadOnlyLogin()
                for _ in 0..<120 {
                    try Task.checkCancellation()
                    try await Task.sleep(for: .seconds(5))
                    await checkScalable()
                    if scalableStatus == "CLI READY" { break }
                }
            } catch is CancellationError {
                return
            } catch {
                scalableStatus = "LOGIN NEEDED"
                scalableErrors += 1
            }
            loginTask = nil
        }
    }
    #endif
}
