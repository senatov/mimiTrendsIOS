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

    @MainActor
    func monitorBoerseWhileActive() async {
        guard scenePhase == .active, MarketProviderAccess.isEnabled(.boerseDAX) else { return }
        let pages = BoerseQuotePages()
        defer { pages.stop() }
        var previousCounts: (german: Int, us: Int)?
        while !Task.isCancelled {
            let sessions = RadarTradingSessions(at: Date())
            let pageSamples = await pages.sample(germanOpen: sessions.german.isTrading, usOpen: sessions.us.isTrading)
            guard !Task.isCancelled else { return }
            var selectedGermanSymbols = Set((marketCycle?.candidates ?? []).map(\.symbol))
            if BoerseDAXSource.knownSymbols.values.contains(where: { $0.symbol == chartSymbol }) {
                selectedGermanSymbols.insert(chartSymbol)
            }
            let samples = BoerseQuoteSelection.selected(pageSamples, germanSymbols: selectedGermanSymbols)
            let germanCount = samples.filter { $0.symbol != nil }.count
            let usCount = Set(samples.filter { $0.symbol == nil }.map(\.isin)).count
            if previousCounts?.german != germanCount || previousCounts?.us != usCount {
                previousCounts = (germanCount, usCount)
                AppDiagnostics.shared.record(.info, "boerse.de", "quote-monitor-coverage",
                                             "dax=\(germanCount) usTech=\(usCount)")
            }
            do {
                if try await boerseQuoteMonitor.accept(samples, settings: RadarScanPreferencesStore.load()) > 0 {
                    await refreshSignals(selectNewest: true)
                }
                try await Task.sleep(for: .seconds(30))
            } catch is CancellationError {
                return
            } catch {
                AppDiagnostics.shared.record(.warning, "boerse.de", "quote-monitor-failed",
                                             "error=\(String(describing: type(of: error)))")
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
            }
        }
    }

    func scanMarketWhileActive() async {
        guard scenePhase == .active else { return }
        while !Task.isCancelled {
            do {
                let enabledProviders = Set(MarketProvider.allCases.filter { MarketProviderAccess.isEnabled($0) })
                let discovered = try await marketScanner.scan(enabledProviders: enabledProviders)
                guard !Task.isCancelled else { return }
                verifiedEIXSymbols = await marketScanner.verifiedEIXSymbols()
                clearUnverifiedSelection()
                if marketCycle == nil { marketCycle = discovered }
                let scan = await marketScanner.scanCandles(discovered,
                    enabled: enabledProviders.contains(.yahoo), prioritySymbol: chartSymbol)
                guard !Task.isCancelled else { return }
                marketCycle = scan.cycle
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
