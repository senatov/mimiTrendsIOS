import SwiftUI

struct RadarSourcePanel: View {
    @ScaledMetric(relativeTo: .caption) private var sourceWidth: CGFloat = 145
    @ScaledMetric(relativeTo: .caption) private var metricWidth: CGFloat = 62
    @ScaledMetric(relativeTo: .caption) private var statusWidth: CGFloat = 124
    @ScaledMetric(relativeTo: .caption) private var actionWidth: CGFloat = 58

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

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Source telemetry")
                .font(.title3.weight(.light))
            Divider()
            GeometryReader { geometry in
                ScrollView([.horizontal, .vertical]) {
                    VStack(spacing: 0) {
                        columnHeadings
                        sourceCard(
                            name: "Yahoo", status: marketStatus(marketCycle?.yahoo),
                            color: marketColor(marketCycle?.yahoo),
                            received: marketCycle?.yahoo.received, valid: marketCycle?.yahoo.valid,
                            operations: marketCycle?.yahoo.operations, errors: marketCycle?.yahoo.errors
                        )
                        sourceCard(
                            name: "Finnhub", status: feedStatus, color: feedColor,
                            received: session.tradeCount, valid: session.completedBarsStored,
                            operations: nil, errors: session.errorCount
                        )
                        ForEach(["Tradegate", "Euronext"], id: \.self) { name in
                            sourceCard(name: name, status: "NOT CONNECTED", color: .secondary,
                                       received: nil, valid: nil, operations: nil, errors: nil)
                        }
                        scalableCard
                        sourceCard(
                            name: "Lang & Schwarz",
                            status: lsStatus == nil ? "CONNECTING" :
                                lsFreshCount > 0 ? "EUR QUOTES" : "NO FRESH QUOTES",
                            color: lsFreshCount > 0 ? .green : .secondary,
                            received: lsStatus?.quotes.count,
                            valid: lsStatus.map { _ in lsFreshCount },
                            operations: lsStatus?.requestCount,
                            errors: lsStatus?.errorCount
                        )
                        sourceCard(
                            name: "wallstreetONLINE", status: discoveryLabel, color: discoveryColor,
                            received: discoveryStatus?.snapshot?.candidates.count,
                            valid: nil, operations: discoveryRequests, errors: discoveryErrors
                        ) {
                            if let snapshot = discoveryStatus?.snapshot {
                                NavigationLink {
                                    DiscoveryCandidateList(snapshot: snapshot)
                                } label: {
                                    Image(systemName: "list.number")
                                }
                                .buttonStyle(TrendsActionButtonStyle(compact: true))
                                .accessibilityLabel("View ranking candidates")
                            }
                        }
                        sourceCard(name: "TraderFox", status: marketStatus(marketCycle?.traderFox),
                                   color: marketColor(marketCycle?.traderFox),
                                   received: marketCycle?.traderFox.received,
                                   valid: marketCycle?.traderFox.valid,
                                   operations: marketCycle?.traderFox.operations,
                                   errors: marketCycle?.traderFox.errors)
                    }
                    .frame(width: max(geometry.size.width, minimumTableWidth), alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .foregroundStyle(TrendsColors.ink)
        .trendsPanel()
        #if os(macOS)
        .task { await checkScalable() }
        .onDisappear { loginTask?.cancel() }
        #endif
    }

    @ViewBuilder
    private var scalableCard: some View {
        #if os(macOS)
        sourceCard(
            name: "Scalable", status: scalableStatus,
            color: .secondary,
            received: nil, valid: nil, operations: scalableChecks, errors: scalableErrors
        ) {
            if scalableStatus == "LOGIN NEEDED" {
                Button("Login") { startScalableLogin() }
                    .buttonStyle(TrendsActionButtonStyle(compact: true))
            }
        }
        #else
        sourceCard(name: "Scalable", status: "NOT CONNECTED", color: .secondary,
                   received: nil, valid: nil, operations: nil, errors: nil)
        #endif
    }

    private func sourceCard<Accessory: View>(
        name: String, status: String, color: Color,
        received: Int?, valid: Int?, operations: Int?, errors: Int?,
        @ViewBuilder accessory: () -> Accessory
    ) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                HStack(spacing: 6) {
                    Circle().fill(color).frame(width: 7, height: 7)
                        .accessibilityHidden(true)
                    Text(name).lineLimit(1)
                }
                .font(.caption)
                .frame(maxWidth: .infinity, alignment: .leading)
                metric("Received", received)
                metric("Valid", valid)
                metric("Requests", operations)
                metric("Errors", errors)
                Text(status)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(status == "NOT CONNECTED" || status == "STOPPED" || status == "CLI READY"
                                     ? TrendsColors.supportingInk : color)
                    .lineLimit(1)
                    .frame(width: statusWidth, alignment: .trailing)
                ZStack(alignment: .trailing) {
                    Color.clear
                    accessory()
                }
                .frame(width: actionWidth, height: 28)
            }
            .frame(maxWidth: .infinity, minHeight: 28)
            .padding(.horizontal, 7)
            paleSeparator
        }
        .accessibilityIdentifier("source-\(name)")
    }

    private func sourceCard(
        name: String, status: String, color: Color,
        received: Int?, valid: Int?, operations: Int?, errors: Int?
    ) -> some View {
        sourceCard(name: name, status: status, color: color,
                   received: received, valid: valid, operations: operations, errors: errors) {
            EmptyView()
        }
    }

    private func metric(_ title: String, _ value: Int?) -> some View {
        Text(value.map { $0.formatted() } ?? "—")
            .font(.caption.monospacedDigit())
            .frame(width: metricWidth, alignment: .trailing)
            .accessibilityLabel("\(title): \(value.map(String.init) ?? "unavailable")")
    }

    private var minimumTableWidth: CGFloat {
        sourceWidth + metricWidth * 4 + statusWidth + actionWidth + 14
    }

    private var columnHeadings: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text("SOURCE").frame(maxWidth: .infinity, alignment: .leading)
                heading("RECEIVED")
                heading("VALID")
                heading("REQUESTS")
                heading("ERRORS")
                Text("STATUS").frame(width: statusWidth, alignment: .trailing)
                Color.clear.frame(width: actionWidth, height: 1)
            }
            .font(.caption2.weight(.medium))
            .foregroundStyle(TrendsColors.supportingInk)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            paleSeparator
        }
    }

    private func heading(_ title: String) -> some View {
        Text(title).frame(width: metricWidth, alignment: .trailing)
    }

    private var paleSeparator: some View {
        Rectangle()
            .fill(Color.blue.opacity(0.16))
            .frame(height: 1)
            .accessibilityHidden(true)
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
        guard let totals else { return .secondary }
        if totals.errors > 0, totals.valid == 0 { return .orange }
        return totals.valid > 0 ? .green : .secondary
    }

    private var discoveryColor: Color {
        discoveryLabel == "RANKING + LINKS" ? .green : .secondary
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
        if session.isSubscribed { return .green }
        if session.errorMessage != nil { return .orange }
        return .secondary
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
