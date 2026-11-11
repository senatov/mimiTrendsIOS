import SwiftUI

extension RadarView {
    func refreshCompanyMetadata() async {
        let symbols = [chartSymbol] + recentSignals.map(\.symbol)
        companyMetadata = await companyMetadataService.cached(symbols: symbols)
        companyMetadata = await companyMetadataService.load(
            symbols: symbols, names: radarCompanyNames
        )
    }

    func refreshDiscoveryWhileActive() async {
        guard scenePhase == .active else {
            discoveryRefreshID = nil
            await discoveryController.stop()
            return
        }
        guard await ensureAutomaticProvidersReady() else { return }
        guard MarketProviderAccess.isOperational(.wallstreetOnline) else {
            discoveryRefreshID = nil
            await discoveryController.stop()
            return
        }
        var firstRefresh = true
        while !Task.isCancelled {
            let nowMillis = Int64(Date().timeIntervalSince1970 * 1_000)
            let isDue = firstRefresh || discoveryStatus.map { nowMillis >= $0.nextAttemptAtMillis } ?? true
            let refreshID = isDue ? UUID() : nil
            discoveryRefreshID = refreshID
            let status = await discoveryController.refresh()
            if discoveryRefreshID == refreshID { discoveryRefreshID = nil }
            guard !Task.isCancelled else { return }
            discoveryStatus = status
            if isDue {
                discoveryRequests += 1
                if !status.lastAttemptSucceeded { discoveryErrors += 1 }
                AppDiagnostics.shared.record(
                    status.lastAttemptSucceeded ? .info : .warning,
                    "Discovery", "refresh-finished",
                    "candidates=\(status.snapshot?.candidates.count ?? 0) success=\(status.lastAttemptSucceeded) nextAttemptMillis=\(status.nextAttemptAtMillis)"
                )
            }
            firstRefresh = false
            do { try await Task.sleep(for: .seconds(60)) }
            catch { return }
        }
    }

    func refreshLSWhileActive() async {
        guard scenePhase == .active else {
            lsStatus = await lsCandidatePool.stop()
            return
        }
        guard await ensureAutomaticProvidersReady() else { return }
        guard MarketProviderAccess.isOperational(.langSchwarz) else {
            lsStatus = await lsCandidatePool.stop()
            return
        }
        while !Task.isCancelled {
            let status = await lsCandidatePool.refreshIfNeeded()
            guard !Task.isCancelled else { return }
            lsStatus = status
            if chartSymbol.hasPrefix("LS:") { chartRefreshID += 1 }
            await refreshSignals()
            do { try await Task.sleep(for: .seconds(30)) }
            catch { return }
        }
    }

    func scanMarketWhileActive() async {
        guard scenePhase == .active else { return }
        while !Task.isCancelled {
            do {
                let enabledProviders = Set(MarketProvider.allCases.filter { MarketProviderAccess.isEnabled($0) })
                let progressBinding = $liveScanProgress
                let cycle = try await marketScanner.scan(
                    settings: RadarScanPreferencesStore.load(), enabledProviders: enabledProviders
                ) { progress in
                    await MainActor.run {
                        guard !Task.isCancelled else { return }
                        progressBinding.wrappedValue = progress
                    }
                }
                guard !Task.isCancelled else { return }
                liveScanProgress = nil
                marketCycle = cycle
                await refreshSignals()
                AppDiagnostics.shared.record(
                    .info, "Radar", "market-scan-finished",
                    "symbols=\(cycle.scannedSymbols) initialScan=\(cycle.initialScanProcessed)/\(cycle.initialScanTotal) yahooErrors=\(cycle.yahoo.errors) candidateSource=\(cycle.usesFMP ? "FMP" : "TraderFox") candidateErrors=\(cycle.usesFMP ? cycle.fmp.errors : cycle.traderFox.errors)"
                )
            } catch is CancellationError {
                return
            } catch {
                AppDiagnostics.shared.record(
                    .error, "Radar", "market-scan-failed",
                    "error=\(String(describing: type(of: error)))"
                )
            }
            do { try await Task.sleep(for: .seconds(15)) }
            catch { return }
        }
    }

    func refreshDisplayCurrency() async {
        guard scenePhase == .active else { return }
        currencyRates = await currencyService.cached()
        do { currencyRates = try await currencyService.latest() }
        catch { AppDiagnostics.shared.record(.warning, "ECB", "fx-rate-unavailable",
                                             "error=\(String(describing: type(of: error)))") }
    }

    func ensureAutomaticProvidersReady() async -> Bool {
        let issues = await MarketProviderStartupGate.shared.check(revision: providerConfigurationRevision)
        // FMP is optional. Keep Radar usable when its plan limit is reached and expose
        // the failed health state in Settings instead of covering the chart on startup.
        providerIssue = issues.first { $0.provider != .fmp }
        providerStartupReady = true
        if !issues.isEmpty {
            AppDiagnostics.shared.record(.warning, "Providers", "preflight-partial",
                "unavailable=\(issues.map { $0.provider.rawValue }.joined(separator: ",")) availableSourcesContinue=true")
        }
        return true
    }

    func retryProvider(_ provider: MarketProvider) {
        Task {
            if provider == .finnhub {
                guard MarketProviderAccess.isEnabled(.finnhub) else { providerIssue = nil; return }
                if let issue = await MarketProviderPreflight().check(.finnhub) {
                    providerIssue = issue
                    return
                }
                providerIssue = nil
                isPreparingFeed = true
                await prepareFeed()
                return
            }
            await MarketProviderStartupGate.shared.invalidate()
            providerConfigurationRevision += 1
            providerIssue = nil
        }
    }

}
