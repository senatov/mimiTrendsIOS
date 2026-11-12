import Foundation
import WebKit

actor BoerseDAXSource {
    fileprivate static let url = URL(string: "https://www.boerse.de/realtime-kurse/Dax-Aktien/DE0008469008")!

    private var nextRefreshAt: Date = .distantPast
    private var lastSuccessfulRefresh: Date?
    private var lastCandidates: [RadarCompanyCandidate] = []

    func candidates(for sessions: RadarTradingSessions, store: RadarCandidateStore?) async throws -> [RadarCompanyCandidate] {
        guard sessions.german.isTrading else { return [] }
        guard Date() >= nextRefreshAt else { return currentCandidates }
        nextRefreshAt = Date().addingTimeInterval(RadarTradingSessions.refreshInterval)
        do {
            lastCandidates = try await loadCandidates()
            lastSuccessfulRefresh = Date()
            do { try await store?.saveCandidateSnapshot(lastCandidates, source: "boerseDAX") }
            catch {
                AppDiagnostics.shared.record(.warning, "boerse.de", "dax-cache-write-failed",
                                             "error=\(String(describing: type(of: error)))")
            }
            MarketProviderAccess.setHealth("Connected", for: .boerseDAX)
            AppDiagnostics.shared.record(.info, "boerse.de", "dax-candidates-loaded",
                                         "candidates=\(lastCandidates.count) phase=\(sessions.german)")
        } catch {
            if Task.isCancelled {
                nextRefreshAt = .distantPast
                throw CancellationError()
            }
            let message = MarketRadarErrorDescription.message(error, provider: "boerse.de DAX")
            MarketProviderAccess.setHealth("Needs attention", for: .boerseDAX, detail: message)
            AppDiagnostics.shared.record(.warning, "boerse.de", "dax-candidate-refresh-failed", message)
        }
        return currentCandidates
    }

    var currentCandidates: [RadarCompanyCandidate] {
        guard let lastSuccessfulRefresh, Date().timeIntervalSince(lastSuccessfulRefresh) < 86_400 else { return [] }
        return lastCandidates
    }

    private func loadCandidates() async throws -> [RadarCompanyCandidate] {
        try await Self.readPage()
    }

    @MainActor
    private static func readPage() async throws -> [RadarCompanyCandidate] {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let page = WKWebView(frame: .zero, configuration: configuration)
        defer { page.stopLoading() }
        page.load(URLRequest(url: url))
        let deadline = ContinuousClock.now + .seconds(20)
        while ContinuousClock.now < deadline {
            try Task.checkCancellation()
            if page.url?.host == url.host, page.url?.path == url.path, !page.isLoading,
               let result = try? await page.evaluateJavaScript(tableScript) as? String,
               let candidates = try? decodePageRows(Data(result.utf8), now: Date()), !candidates.isEmpty {
                AppDiagnostics.shared.record(.info, "boerse.de", "dax-page-parsed", "rows=\(candidates.count)")
                return candidates
            }
            try await Task.sleep(for: .milliseconds(500))
        }
        throw RadarSourceError.invalidResponse
    }

    fileprivate static let tableScript = """
        (() => {
            const controls = [...document.querySelectorAll('button, [role="button"], input[type="button"]')];
            const accept = controls.find(el => {
                const label = (el.innerText || el.value || el.getAttribute('aria-label') || '').trim();
                return /^(alle (cookies )?(akzeptieren|erlauben|zulassen)|accept all( cookies)?|alles akzeptieren)$/i.test(label)
                    && el.getClientRects().length > 0;
            });
            if (accept) accept.click();
            const rows = document.querySelectorAll('#TableBody_0 table tr');
            return JSON.stringify([...rows].map(row => ({
                text: [...row.cells].map(cell => cell.innerText.trim()),
                markup: row.innerHTML
            })));
        })()
        """
    struct PageRow: Decodable {
        let text: [String]
        let markup: String
    }

    static func decodePageRows(_ data: Data, now: Date) throws -> [RadarCompanyCandidate] {
        let rows = try JSONDecoder().decode([PageRow].self, from: data)
        let ranked = rows.compactMap { row -> (RadarCompanyCandidate, Double)? in
            guard row.text.count == 14 else { return nil }
            let isin = MarketPageHTML.first(#"\b([A-Z]{2}[A-Z0-9]{9}[0-9])\b"#, in: row.markup)
            guard let company = isin.flatMap({ knownSymbols[$0] })
                ?? knownSymbols.values.first(where: { $0.name.caseInsensitiveCompare(row.text[1]) == .orderedSame })
            else { return nil }
            let changeText = row.text[7].replacingOccurrences(of: "−", with: "-")
                .replacingOccurrences(of: ",", with: ".")
                .replacingOccurrences(of: "%", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let change = Double(changeText)
            let isFresh = MarketPageHTML.quoteTime(row.text[12], now: now) != nil
                && MarketPageHTML.germanNumber(row.text[5]) != nil
            let rank = isFresh ? change.flatMap { $0.isFinite ? abs($0) : nil } ?? -1 : -1
            return (RadarCompanyCandidate(symbol: company.symbol, name: company.name), rank)
        }.sorted { $0.1 == $1.1 ? $0.0.symbol < $1.0.symbol : $0.1 > $1.1 }
        var seen = Set<String>()
        return ranked.map(\.0).filter { seen.insert($0.symbol).inserted }
    }

    // Constituents observed in the DAX page's Stuttgart request.
    static let knownSymbols: [String: (symbol: String, name: String)] = [
        "DE000A1EWWW0": ("ADS.DE", "Adidas"),
        "NL0000235190": ("AIR.DE", "Airbus"),
        "DE0008404005": ("ALV.DE", "Allianz"),
        "DE000BASF111": ("BAS.DE", "BASF"),
        "DE000BAY0017": ("BAYN.DE", "Bayer"),
        "DE0005200000": ("BEI.DE", "Beiersdorf"),
        "DE0005190003": ("BMW.DE", "BMW"),
        "DE000A1DAHH0": ("BNR.DE", "Brenntag"),
        "DE000CBK1001": ("CBK.DE", "Commerzbank"),
        "DE0005439004": ("CON.DE", "Continental"),
        "DE000DTR0CK8": ("DTG.DE", "Daimler Truck"),
        "DE0005140008": ("DBK.DE", "Deutsche Bank"),
        "DE0005810055": ("DB1.DE", "Deutsche Börse"),
        "DE0005557508": ("DTE.DE", "Deutsche Telekom"),
        "DE0005552004": ("DHL.DE", "DHL Group"),
        "DE000ENAG999": ("EOAN.DE", "E.ON"),
        "DE000FRE5EN2": ("FRE.DE", "Fresenius"),
        "DE0005785802": ("FME.DE", "Fresenius Medical Care"),
        "DE0006602006": ("G1A.DE", "GEA Group"),
        "DE0008402215": ("HNR1.DE", "Hannover Rück"),
        "DE0006047004": ("HEI.DE", "Heidelberg Materials"),
        "DE0006048432": ("HEN3.DE", "Henkel"),
        "DE0006070006": ("HOT.DE", "Hochtief"),
        "DE0006231004": ("IFX.DE", "Infineon"),
        "DE0007100000": ("MBG.DE", "Mercedes-Benz Group"),
        "DE0006599905": ("MRK.DE", "Merck"),
        "DE000A0D9PT0": ("MTX.DE", "MTU Aero Engines"),
        "DE0008430026": ("MUV2.DE", "Munich Re"),
        "NL0015002SN0": ("QIA.DE", "Qiagen"),
        "DE0007030009": ("RHM.DE", "Rheinmetall"),
        "DE0007037129": ("RWE.DE", "RWE"),
        "DE0007164600": ("SAP.DE", "SAP"),
        "DE000A12DM80": ("G24.DE", "Scout24"),
        "DE0007236101": ("SIE.DE", "Siemens"),
        "DE000ENER6Y0": ("ENR.DE", "Siemens Energy"),
        "DE000SHL1006": ("SHL.DE", "Siemens Healthineers"),
        "DE000SYM9999": ("SY1.DE", "Symrise"),
        "DE0007664039": ("VOW3.DE", "Volkswagen"),
        "DE000A1ML7J1": ("VNA.DE", "Vonovia"),
        "DE000ZAL1111": ("ZAL.DE", "Zalando"),
    ]
}

/// Uses the rendered lists; the web pages themselves keep their quotes current.
@MainActor
final class BoerseQuotePages {
    private static let usURL = URL(string: "https://www.boerse.de/realtime-kurse/US-Tech-100-Aktien/US6311011026")!
    private static let retryInterval = BoerseQuoteRetryPolicy.minimumRetrySeconds
    private let configuration: WKWebViewConfiguration
    private var pages: [Int: WKWebView] = [:]
    private var secondPageBaseline: Set<String>?
    private var secondPageVerified = false
    private var startedAt: [Int: Date] = [:]
    private var lastReloadAt: [Int: Date] = [:]
    private var lastStaleReportAt: [Int: Date] = [:]
    private var lastProgressAt: [Int: Date] = [:]
    private var latestQuoteMillis: [Int: Int64] = [:]
    private var staleSlots = Set<Int>()

    init() {
        configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
    }

    func sample(germanOpen: Bool, usOpen: Bool) async -> [BoerseQuoteSample] {
        var samples: [BoerseQuoteSample] = []
        for (slot, url, open) in [(0, BoerseDAXSource.url, germanOpen), (1, Self.usURL, usOpen),
                                  (2, Self.usURL, usOpen)] {
            guard !Task.isCancelled else { break }
            guard open else { reset(slot); continue }
            if pages[slot] == nil {
                let view = WKWebView(frame: .zero, configuration: configuration)
                pages[slot] = view
                startedAt[slot] = Date()
                lastProgressAt[slot] = Date()
                view.load(URLRequest(url: url))
                continue
            }
            guard let view = pages[slot] else { continue }
            if view.isLoading || view.url?.host != url.host {
                retryIfNeeded(slot: slot, view: view, url: url, now: Date(),
                              reason: view.isLoading ? "loading" : "wrong-host")
                continue
            }
            guard let json = try? await view.evaluateJavaScript(BoerseDAXSource.tableScript) as? String,
                  let rows = try? JSONDecoder().decode([BoerseDAXSource.PageRow].self, from: Data(json.utf8))
            else {
                retryIfNeeded(slot: slot, view: view, url: url, now: Date(), reason: "script-or-decode")
                continue
            }
            let identifiers = Set(rows.compactMap { Self.isin(in: $0.markup) })
            if slot == 2 && !secondPageVerified {
                if let baseline = secondPageBaseline, !identifiers.subtracting(baseline).isEmpty {
                    secondPageVerified = true
                    AppDiagnostics.shared.record(.info, "boerse.de", "us-tech-second-page-loaded",
                                                 "identifiers=\(identifiers.count)")
                } else if secondPageBaseline == nil, !identifiers.isEmpty,
                          (try? await view.evaluateJavaScript(Self.secondPageScript) as? Bool) == true {
                    secondPageBaseline = identifiers
                    startedAt[slot] = Date()
                    lastProgressAt[slot] = Date()
                    continue
                } else {
                    retryIfNeeded(slot: slot, view: view, url: url, now: Date(),
                                  reason: "second-page-unavailable", details: "identifiers=\(identifiers.count)")
                    continue
                }
            }
            let now = Date()
            let result = BoerseQuoteRows.decode(rows, now: now, slot: slot)
            if let newest = result.newestQuoteMillis, newest > (latestQuoteMillis[slot] ?? 0) {
                latestQuoteMillis[slot] = newest
                lastProgressAt[slot] = now
            }
            if result.samples.isEmpty {
                retryIfNeeded(slot: slot, view: view, url: url, now: now,
                              reason: "no-fresh-rows", details: result.diagnostics,
                              youngestAgeSeconds: result.youngestAgeSeconds)
            } else {
                startedAt[slot] = now
                if staleSlots.remove(slot) != nil {
                    AppDiagnostics.shared.record(.info, "boerse.de", "quote-page-recovered",
                                                 "page=\(slot) \(result.diagnostics)")
                    lastStaleReportAt[slot] = nil
                }
            }
            samples.append(contentsOf: result.samples)
        }
        return samples
    }

    func stop() {
        for slot in Array(pages.keys) { reset(slot) }
    }

    private func reset(_ slot: Int) {
        pages.removeValue(forKey: slot)?.stopLoading()
        startedAt[slot] = nil
        lastReloadAt[slot] = nil
        lastStaleReportAt[slot] = nil
        lastProgressAt[slot] = nil
        latestQuoteMillis[slot] = nil
        staleSlots.remove(slot)
        if slot == 2 {
            secondPageBaseline = nil
            secondPageVerified = false
        }
    }

    private func retryIfNeeded(slot: Int, view: WKWebView, url: URL, now: Date,
                               reason: String, details: String = "", youngestAgeSeconds: Int? = nil) {
        guard now.timeIntervalSince(startedAt[slot] ?? now) >= 45 else { return }
        staleSlots.insert(slot)
        let progressAge = Int(now.timeIntervalSince(lastProgressAt[slot] ?? startedAt[slot] ?? now))
        if now.timeIntervalSince(lastStaleReportAt[slot] ?? .distantPast) >= Self.retryInterval {
            AppDiagnostics.shared.record(.warning, "boerse.de", "quote-page-stale",
                "page=\(slot) reason=\(reason) progressAgeSeconds=\(progressAge) \(details)")
            lastStaleReportAt[slot] = now
        }
        let staleDuration = now.timeIntervalSince(startedAt[slot] ?? now)
        guard BoerseQuoteRetryPolicy.shouldReload(
            staleSeconds: staleDuration, progressSeconds: TimeInterval(progressAge),
            sinceReloadSeconds: now.timeIntervalSince(lastReloadAt[slot] ?? .distantPast),
            quoteAgeSeconds: youngestAgeSeconds, pageUnavailable: reason != "no-fresh-rows"
        ) else { return }
        AppDiagnostics.shared.record(.warning, "boerse.de", "quote-page-retry",
                                     "page=\(slot) reason=\(reason) progressAgeSeconds=\(progressAge) youngestAgeSeconds=\(youngestAgeSeconds ?? -1)")
        lastReloadAt[slot] = now
        startedAt[slot] = now
        lastProgressAt[slot] = now
        if slot == 2 {
            secondPageBaseline = nil
            secondPageVerified = false
        }
        view.load(URLRequest(url: url))
    }

    private static func isin(in markup: String) -> String? {
        MarketPageHTML.first(#"\b([A-Z]{2}[A-Z0-9]{9}[0-9])\b"#, in: markup)
    }

    private static let secondPageScript = #"""
    (() => {
        const root = document.querySelector('#TableBody_0');
        const table = root?.querySelector('table');
        if (!table) return false;
        const buttons = [...document.querySelectorAll('a, button, [role="button"]')];
        const next = buttons.find(el => {
            if (!(table.compareDocumentPosition(el) & Node.DOCUMENT_POSITION_FOLLOWING)) return false;
            if (!el.getClientRects().length || el.getAttribute('aria-disabled') === 'true') return false;
            const label = (el.innerText || '').trim();
            const hint = [el.getAttribute('rel'), el.getAttribute('title'), el.getAttribute('aria-label')].join(' ');
            if (/^(2|Seite 2)$/.test(label)) return true;
            return /\b(next|weiter|nächste)\b/i.test(hint)
                && !!el.closest('[class*="pag"], [id*="pag"], nav');
        });
        if (!next) return false;
        if (next.href && /^https?:/.test(next.href) && new URL(next.href).origin !== location.origin) return false;
        next.click();
        return true;
    })()
    """#
}
