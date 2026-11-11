import Foundation

actor BoerseDAXSource {
    private static let url = URL(string: "https://www.boerse.de/realtime-kurse/Dax-Aktien/DE0008469008")!
    private let session: URLSession
    private var resolved: [String: String] = [:]

    private var previousSessions: RadarTradingSessions?
    private var nextRefreshAt: Date = .distantPast
    private var lastCandidates: [RadarCompanyCandidate] = []

    init(session: URLSession = .shared) { self.session = session }

    func candidates(for sessions: RadarTradingSessions) async throws -> [RadarCompanyCandidate] {
        let changed = previousSessions?.german != sessions.german
            || previousSessions?.germanOpeningSoon != sessions.germanOpeningSoon
        guard sessions.german.isTrading else {
            previousSessions = sessions
            lastCandidates = []
            return []
        }
        guard changed || Date() >= nextRefreshAt else { return lastCandidates }
        do {
            lastCandidates = try await loadCandidates()
            nextRefreshAt = Date().addingTimeInterval(RadarTradingSessions.refreshInterval)
            MarketProviderAccess.setHealth("Connected", for: .boerseDAX)
            AppDiagnostics.shared.record(.info, "boerse.de", "dax-candidates-loaded",
                                         "candidates=\(lastCandidates.count) phase=\(sessions.german)")
        } catch {
            try Task.checkCancellation()
            nextRefreshAt = Date().addingTimeInterval(60)
            let message = MarketRadarErrorDescription.message(error, provider: "boerse.de DAX")
            MarketProviderAccess.setHealth("Needs attention", for: .boerseDAX, detail: message)
            AppDiagnostics.shared.record(.warning, "boerse.de", "dax-candidate-refresh-failed", message)
        }
        previousSessions = sessions
        return lastCandidates
    }

    private func loadCandidates() async throws -> [RadarCompanyCandidate] {
        var request = URLRequest(url: Self.url)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        request.setValue("Mozilla/5.0 MiMiTrends", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw RadarSourceError.invalidResponse }
        guard http.statusCode == 200 else { throw RadarSourceError.httpStatus(http.statusCode) }
        guard data.count <= 8_000_000 else { throw RadarSourceError.invalidResponse }
        let rows = Self.rows(in: String(decoding: data, as: UTF8.self), now: Date())
        guard !rows.isEmpty else { throw RadarSourceError.invalidResponse }
        let missing = rows.map(\.isin).filter { Self.knownSymbols[$0] == nil && resolved[$0] == nil }
        for start in stride(from: 0, to: missing.count, by: 4) {
            try Task.checkCancellation()
            await withTaskGroup(of: (String, String?).self) { group in
                for isin in missing[start..<min(start + 4, missing.count)] {
                    group.addTask { (isin, try? await RadarBaselineSource.searchISIN(isin, germanOnly: true)) }
                }
                for await (isin, symbol) in group { resolved[isin] = symbol }
            }
        }
        try Task.checkCancellation()
        let candidates = rows.compactMap { row -> RadarCompanyCandidate? in
            guard let symbol = Self.knownSymbols[row.isin] ?? resolved[row.isin] else { return nil }
            return RadarCompanyCandidate(symbol: symbol, name: row.name)
        }
        guard !candidates.isEmpty else { throw RadarSourceError.invalidResponse }
        if candidates.count != rows.count {
            AppDiagnostics.shared.record(.warning, "boerse.de", "dax-symbols-unresolved",
                                         "rows=\(rows.count) resolved=\(candidates.count)")
        }
        return candidates
    }

    struct Row {
        let isin: String
        let name: String
        let change: Double
    }

    static func rows(in html: String, now: Date) -> [Row] {
        let heading = #"(?i)Kursliste\s+Realtime\s+Dax-Aktien"#
        guard let start = html.range(of: heading, options: .regularExpression),
              let table = MarketPageHTML.first(#"(?i)<table\b[^>]*>(.*?)</table>"#, in: String(html[start.upperBound...]))
        else { return [] }
        var seen = Set<String>()
        return MarketPageHTML.matches(#"(?i)<tr\b[^>]*>(.*?)</tr>"#, in: table).compactMap { row in
            let cells = MarketPageHTML.matches(#"(?i)<td\b[^>]*>(.*?)</td>"#, in: row)
            guard let index = cells.firstIndex(where: { $0.localizedCaseInsensitiveContains("-Aktie/")
                      || $0.localizedCaseInsensitiveContains("/aktien/") }),
                  cells.count > index + 4,
                  let isin = MarketPageHTML.first(#"/([A-Z]{2}[A-Z0-9]{9}[0-9])(?:[/?#"'&]|\b)"#, in: cells[index]),
                  MarketPageHTML.germanNumber(cells[index + 1]) != nil,
                  let time = MarketPageHTML.first(#"(\b\d{2}:\d{2}:\d{2}\b)"#, in: cells[index + 4]),
                  MarketPageHTML.quoteTime(time, now: now) != nil
            else { return nil }
            let changeText = MarketPageHTML.plainText(cells[index + 3])
                .replacingOccurrences(of: "−", with: "-")
                .replacingOccurrences(of: ".", with: "")
                .replacingOccurrences(of: ",", with: ".")
                .replacingOccurrences(of: #"[^0-9.+-]"#, with: "", options: .regularExpression)
            let name = MarketPageHTML.plainText(cells[index])
            guard let change = Double(changeText), change.isFinite, !name.isEmpty,
                  seen.insert(isin).inserted else { return nil }
            return Row(isin: isin, name: name, change: change)
        }.sorted { abs($0.change) == abs($1.change) ? $0.isin < $1.isin : abs($0.change) > abs($1.change) }
    }

    // Resolve common constituents locally so a list refresh does not require 40 searches.
    private static let knownSymbols = [
        "DE000A1EWWW0": "ADS.DE", "NL0000235190": "AIR.DE", "DE0008404005": "ALV.DE",
        "DE000BASF111": "BAS.DE", "DE000BAY0017": "BAYN.DE", "DE0005200000": "BEI.DE",
        "DE0005190003": "BMW.DE", "DE000A1DAHH0": "BNR.DE", "DE000CBK1001": "CBK.DE",
        "DE0005439004": "CON.DE", "DE000DTR0CK8": "DTG.DE", "DE0005140008": "DBK.DE",
        "DE0005810055": "DB1.DE", "DE0005557508": "DTE.DE", "DE0005552004": "DHL.DE",
        "DE000ENAG999": "EOAN.DE", "DE0005785604": "FRE.DE", "DE0005785802": "FME.DE",
        "DE0006602006": "G1A.DE", "DE0008402215": "HNR1.DE", "DE0006047004": "HEI.DE",
        "DE0006048432": "HEN3.DE", "DE0006070006": "HOT.DE", "DE0006231004": "IFX.DE",
        "DE0007100000": "MBG.DE", "DE0006599905": "MRK.DE", "DE000A0D9PT0": "MTX.DE",
        "DE0008430026": "MUV2.DE", "NL0015002CX3": "QIA.DE", "DE0007030009": "RHM.DE",
        "DE0007037129": "RWE.DE", "DE0007164600": "SAP.DE", "DE000A12DM80": "G24.DE",
        "DE0007236101": "SIE.DE", "DE000ENER6Y0": "ENR.DE", "DE000SHL1006": "SHL.DE",
        "DE000SYM9999": "SY1.DE", "DE0007664039": "VOW3.DE", "DE000A1ML7J1": "VNA.DE",
        "DE000ZAL1111": "ZAL.DE"
    ]
}
