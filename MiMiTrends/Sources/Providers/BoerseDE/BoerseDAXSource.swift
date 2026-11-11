import Foundation
import WebKit

actor BoerseDAXSource {
    private static let url = URL(string: "https://www.boerse.de/realtime-kurse/Dax-Aktien/DE0008469008")!

    private var nextRefreshAt: Date = .distantPast
    private var lastSuccessfulRefresh: Date?
    private var lastCandidates: [RadarCompanyCandidate] = []

    func candidates(for sessions: RadarTradingSessions, store: MarketBarStore?) async throws -> [RadarCompanyCandidate] {
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
        let script = """
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
        while ContinuousClock.now < deadline {
            try Task.checkCancellation()
            if page.url?.host == url.host, page.url?.path == url.path, !page.isLoading,
               let result = try? await page.evaluateJavaScript(script) as? String,
               let candidates = try? decodePageRows(Data(result.utf8), now: Date()), !candidates.isEmpty {
                AppDiagnostics.shared.record(.info, "boerse.de", "dax-page-parsed", "rows=\(candidates.count)")
                return candidates
            }
            try await Task.sleep(for: .milliseconds(500))
        }
        throw RadarSourceError.invalidResponse
    }

    private struct PageRow: Decodable {
        let text: [String]
        let markup: String
    }

    static func decodePageRows(_ data: Data, now: Date) throws -> [RadarCompanyCandidate] {
        let rows = try JSONDecoder().decode([PageRow].self, from: data)
        let ranked = rows.compactMap { row -> (RadarCompanyCandidate, Double)? in
            guard row.text.count == 14,
                  MarketPageHTML.germanNumber(row.text[5]) != nil,
                  MarketPageHTML.quoteTime(row.text[12], now: now) != nil
            else { return nil }
            let isin = MarketPageHTML.first(#"\b([A-Z]{2}[A-Z0-9]{9}[0-9])\b"#, in: row.markup)
            guard let company = isin.flatMap({ knownSymbols[$0] })
                ?? knownSymbols.values.first(where: { $0.name.caseInsensitiveCompare(row.text[1]) == .orderedSame })
            else { return nil }
            let changeText = row.text[7].replacingOccurrences(of: "−", with: "-")
                .replacingOccurrences(of: ",", with: ".")
                .replacingOccurrences(of: "%", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let change = Double(changeText), change.isFinite else { return nil }
            return (RadarCompanyCandidate(symbol: company.symbol, name: company.name), abs(change))
        }.sorted { $0.1 == $1.1 ? $0.0.symbol < $1.0.symbol : $0.1 > $1.1 }
        var seen = Set<String>()
        return ranked.map(\.0).filter { seen.insert($0.symbol).inserted }
    }

    // Constituents observed in the DAX page's Stuttgart request.
    private static let knownSymbols: [String: (symbol: String, name: String)] = [
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
