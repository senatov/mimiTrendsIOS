import SwiftUI

extension RadarView {
    func refreshCompanyMetadata() async {
        let symbols = [chartSymbol] + visibleSignals.map(\.symbol)
        companyMetadata = await companyMetadataService.cached(symbols: symbols)
        companyMetadata = await companyMetadataService.load(
            symbols: symbols, names: radarCompanyNames
        )
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
            do { try await Task.sleep(for: .seconds(30)) }
            catch { return }
        }
    }

    func refreshSignalHistoryWhileActive() async {
        guard scenePhase == .active else { return }
        while !Task.isCancelled {
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
                let retained = recentSignals.filter {
                    $0.dataStatus == YahooCandleSignalPipeline.volumeValidatedStatus ||
                        $0.dataStatus == YahooCandleSignalPipeline.delayedVolumeValidatedStatus
                }.map(\.symbol)
                let discovered = try await marketScanner.scan(
                    enabledProviders: enabledProviders, retainedSymbols: retained)
                guard !Task.isCancelled else { return }
                verifiedEIXSymbols = await marketScanner.verifiedEIXSymbols()
                if marketCycle == nil { marketCycle = discovered }
                let scan = await marketScanner.scanCandles(discovered,
                    enabled: enabledProviders.contains(.yahoo), prioritySymbol: chartSymbol,
                    retainedSymbols: retained)
                guard !Task.isCancelled else { return }
                marketCycle = scan.cycle
                clearUnverifiedSelection()
                if scan.recordedSignal { await refreshSignals() }
                AppDiagnostics.shared.record(
                    .info, "Radar", "candidate-pool-ready",
                    "candidates=\(scan.cycle.candidates.count) checked=\(scan.cycle.progress.processed) usable=\(scan.cycle.progress.successful) tradingViewErrors=\(scan.cycle.tradingView.errors)"
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
        providerIssue = issues.first
        providerStartupReady = true
        if !issues.isEmpty {
            AppDiagnostics.shared.record(.warning, "Providers", "preflight-partial",
                "unavailable=\(issues.map { $0.provider.rawValue }.joined(separator: ",")) availableSourcesContinue=true")
        }
        return true
    }

    func retryProvider(_ provider: MarketProvider) {
        Task {
            await MarketProviderStartupGate.shared.invalidate()
            providerConfigurationRevision += 1
            providerIssue = nil
        }
    }

}
