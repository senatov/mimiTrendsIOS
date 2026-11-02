import SwiftUI

struct RadarSourcePanel: View {
    @Environment(RadarTableColorStore.self) private var tableColors
    @Environment(\.colorScheme) private var colorScheme
    @ScaledMetric(relativeTo: .body) private var sourceWidth: CGFloat = 190
    @ScaledMetric(relativeTo: .body) private var metricWidth: CGFloat = 62
    @ScaledMetric(relativeTo: .body) private var statusWidth: CGFloat = 124

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
                            sourceCard(name: name, status: "NOT CONNECTED", color: tableColor(.sourceInactive),
                                       received: nil, valid: nil, operations: nil, errors: nil)
                        }
                        scalableCard
                        sourceCard(
                            name: "Lang & Schwarz",
                            status: lsStatus == nil ? "CONNECTING" :
                                lsFreshCount > 0 ? "EUR QUOTES" : "NO FRESH QUOTES",
                        color: lsFreshCount > 0 ? tableColor(.sourceActive) : tableColor(.sourceInactive),
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
                                .buttonStyle(TrendsActionButtonStyle(tint: tableColor(.actionAccent), compact: true))
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
        .foregroundStyle(tableColor(.bodyText))
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
            color: tableColor(.sourceInactive),
            received: nil, valid: nil, operations: scalableChecks, errors: scalableErrors
        ) {
            if scalableStatus == "LOGIN NEEDED" {
                Button("Login") { startScalableLogin() }
                    .buttonStyle(TrendsActionButtonStyle(tint: tableColor(.actionAccent), compact: true))
            }
        }
        #else
        sourceCard(name: "Scalable", status: "NOT CONNECTED", color: tableColor(.sourceInactive),
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
                HStack(spacing: 7) {
                    HStack(spacing: 6) {
                        Circle().fill(color).frame(width: 7, height: 7)
                            .accessibilityHidden(true)
                        Text(name)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .layoutPriority(-1)
                    }
                    accessory()
                        .fixedSize(horizontal: true, vertical: false)
                        .layoutPriority(1)
                }
                .font(.body)
                .frame(width: sourceWidth, alignment: .leading)
                .clipped()
                metric("Received", received)
                metric("Valid", valid)
                metric("Requests", operations)
                metric("Errors", errors)
                Text(status)
                    .font(.body)
                    .foregroundStyle(status == "NOT CONNECTED" || status == "STOPPED" || status == "CLI READY"
                                     ? tableColor(.sourceInactive) : color)
                    .lineLimit(1)
                    .frame(width: statusWidth, alignment: .trailing)
            }
            .frame(maxWidth: .infinity, minHeight: 30)
            .padding(.horizontal, 7)
            .overlay(sourceColumnLines)
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
            .font(.body.monospacedDigit())
            .frame(width: metricWidth, alignment: .trailing)
            .accessibilityLabel("\(title): \(value.map(String.init) ?? "unavailable")")
    }

    private var minimumTableWidth: CGFloat {
        sourceWidth + metricWidth * 4 + statusWidth + 14
    }

    private var columnHeadings: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text("SOURCE").frame(width: sourceWidth, alignment: .leading)
                heading("RECV", fullTitle: "Received")
                heading("VALID", fullTitle: "Valid")
                heading("REQ", fullTitle: "Requests")
                heading("ERR", fullTitle: "Errors")
                Text("STATUS").frame(width: statusWidth, alignment: .trailing)
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(tableColor(.headerText))
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .overlay(sourceColumnLines)
            .background(tableColor(.headerFill))
            paleSeparator
        }
    }

    private func heading(_ title: String, fullTitle: String) -> some View {
        Text(title)
            .lineLimit(1)
            .frame(width: metricWidth, alignment: .trailing)
            .help(fullTitle)
            .accessibilityLabel(fullTitle)
    }

    private var paleSeparator: some View {
        Rectangle()
            .fill(tableColor(.grid))
            .frame(height: 1)
            .accessibilityHidden(true)
    }

    private var sourceColumnLines: some View {
        GeometryReader { geometry in
            Path { path in
                for index in 0...4 {
                    let x = 7 + sourceWidth + metricWidth * CGFloat(index)
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: geometry.size.height))
                }
            }
            .stroke(tableColor(.grid), lineWidth: 1)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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
