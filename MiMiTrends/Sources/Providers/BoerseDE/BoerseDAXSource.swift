import Foundation

actor BoerseDAXSource {
    private static let url = URL(string: "https://realtime-push.boerse.de/marketstates/realtime/")!
    private let session: URLSession

    private var nextRefreshAt: Date = .distantPast
    private var lastSuccessfulRefresh: Date?
    private var lastCandidates: [RadarCompanyCandidate] = []

    init(session: URLSession = .shared) { self.session = session }

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
        var request = URLRequest(url: Self.url)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/javascript, */*; q=0.01", forHTTPHeaderField: "Accept")
        request.setValue("https://www.boerse.de", forHTTPHeaderField: "Origin")
        request.setValue("https://www.boerse.de/", forHTTPHeaderField: "Referer")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15",
                         forHTTPHeaderField: "User-Agent")
        request.httpBody = Data(Self.knownSymbols.keys.sorted().map {
            "marketstateQuery%5B%5D=\($0)%40STU"
        }.joined(separator: "&").utf8)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw RadarSourceError.invalidResponse }
        AppDiagnostics.shared.record(.info, "boerse.de", "dax-xhr-response",
                                     "http=\(http.statusCode) bytes=\(data.count)")
        guard http.statusCode == 200 else { throw RadarSourceError.httpStatus(http.statusCode) }
        guard (1...1_000_000).contains(data.count) else { throw RadarSourceError.invalidResponse }
        return try Self.decodeCandidates(data, now: Date())
    }

    static func decodeCandidates(_ data: Data, now: Date) throws -> [RadarCompanyCandidate] {
        let envelope = try JSONDecoder().decode(RealtimeResponse.self, from: data)
        guard envelope.success, let items = envelope.data?.items else { throw RadarSourceError.invalidResponse }
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let wholeSecondsFormatter = ISO8601DateFormatter()
        var ranked: [(candidate: RadarCompanyCandidate, change: Double)] = []
        for item in items {
            let parts = item.marketstateQuery.split(separator: "@")
            guard parts.count == 2, parts[1] == "STU", item.stale == false,
                  let company = knownSymbols[String(parts[0])],
                  let quote = item.marketstate?.last, quote.value > 0,
                  let change = item.marketstate?.performance?.changeRelative, change.isFinite,
                  let date = dateFormatter.date(from: quote.datetime)
                    ?? wholeSecondsFormatter.date(from: quote.datetime),
                  (-30...600).contains(now.timeIntervalSince(date))
            else { continue }
            ranked.append((RadarCompanyCandidate(symbol: company.symbol, name: company.name), abs(change)))
        }
        ranked.sort {
            $0.change == $1.change ? $0.candidate.symbol < $1.candidate.symbol : $0.change > $1.change
        }
        var seen = Set<String>()
        let candidates = ranked.map(\.candidate).filter { seen.insert($0.symbol).inserted }
        guard !candidates.isEmpty else { throw RadarSourceError.invalidResponse }
        return candidates
    }

    private struct RealtimeResponse: Decodable {
        let success: Bool
        let data: Payload?

        struct Payload: Decodable { let items: [Item] }
        struct Item: Decodable {
            let marketstateQuery: String
            let stale: Bool?
            let marketstate: MarketState?
        }
        struct MarketState: Decodable {
            let last: Quote?
            let performance: Performance?
        }
        struct Quote: Decodable {
            let value: Double
            let datetime: String
        }
        struct Performance: Decodable { let changeRelative: Double? }
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
