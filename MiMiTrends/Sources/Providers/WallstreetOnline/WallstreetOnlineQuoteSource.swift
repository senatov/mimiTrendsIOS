import Foundation

struct WallstreetOnlineQuote: Sendable, Equatable {
    let instrumentID: String
    let priceEUR: Double
    let sourceCurrency: String
    let sourcePrice: Double
    let euroUSDRate: Double?
    let fxObservedAtMillis: Int64?
    let observedAtMillis: Int64
}

struct WallstreetOnlineQuoteSource: Sendable {
    private let session: URLSession

    private var baseURL: URL {
        let configured = ProviderEndpointStore.url(for: .wallstreetOnline)
        return configured.host == "www.wallstreet-online.de"
            ? configured : URL(string: ProviderEndpoint.wallstreetOnline.defaultURL)!
    }

    init(session: URLSession = .shared) { self.session = session }

    func loadEURUSD() async throws -> (rate: Double, observedAt: Int64) {
        let url = URL(string: "/devisen/euro-us-dollar-eur-usd-kurs", relativeTo: baseURL)!.absoluteURL
        return try Self.decodeEURUSD(try await load(url), now: Date())
    }

    func loadQuotes(for candidates: [DiscoveryCandidate]) async throws -> [String: WallstreetOnlineQuote] {
        let selected = Array(candidates.prefix(8))
        var pages: [(String, Data)] = []
        for candidate in selected {
            try Task.checkCancellation()
            guard candidate.instrumentID.range(
                of: "^/aktien/[a-z0-9]+(-[a-z0-9]+)*$", options: .regularExpression
            ) != nil,
                  let url = URL(string: candidate.instrumentID,
                                relativeTo: baseURL)?.absoluteURL else {
                continue
            }
            do {
                let data = try await load(url, expectedPath: candidate.instrumentID)
                pages.append((candidate.instrumentID, data))
            } catch {
                AppDiagnostics.shared.record(.warning, "wallstreetONLINE", "quote-page-fetch-failed",
                    "path=\(candidate.instrumentID) error=\(String(describing: error))")
            }
        }
        let needsFX = pages.contains { _, data in
            String(data: data, encoding: .utf8).map { Self.currency(in: $0) == "USD" } ?? false
        }
        let fx: (rate: Double, observedAt: Int64)?
        if needsFX {
            do {
                fx = try await loadEURUSD()
                if let fx {
                    AppDiagnostics.shared.record(.info, "wallstreetONLINE", "usd-fx-loaded",
                        "rate=\(fx.rate) observedAt=\(fx.observedAt)")
                }
            } catch {
                fx = nil
                AppDiagnostics.shared.record(.warning, "wallstreetONLINE", "usd-fx-unavailable",
                    "error=\(String(describing: error)) usdQuotesWillBeSkipped=true")
            }
        } else {
            fx = nil
        }
        var result: [String: WallstreetOnlineQuote] = [:]
        var decodeFailures = 0
        var skippedUSD = 0
        for (path, data) in pages {
            do {
                let quote = try Self.decode(data, instrumentID: path, euroUSD: fx, now: Date())
                result[path] = quote
            } catch {
                decodeFailures += 1
                if String(data: data, encoding: .utf8).map({ Self.currency(in: $0) == "USD" }) == true {
                    skippedUSD += 1
                }
                AppDiagnostics.shared.record(.warning, "wallstreetONLINE", "quote-page-decode-failed",
                    "path=\(path) error=\(String(describing: error))")
            }
        }
        AppDiagnostics.shared.record(.info, "wallstreetONLINE", "quote-batch-complete",
            "requested=\(selected.count) fetched=\(pages.count) decoded=\(result.count) failures=\(decodeFailures) usdSkipped=\(skippedUSD)")
        return result
    }

    private func load(_ url: URL, expectedPath: String? = nil) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("text/html", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              http.url?.scheme == "https", http.url?.host == "www.wallstreet-online.de",
              expectedPath.map({ http.url?.path == $0 }) ?? true,
              data.count <= 2_000_000 else { throw WallstreetOnlineQuoteError.invalidPage }
        return data
    }

    static func decodeEURUSD(_ data: Data, now: Date) throws -> (rate: Double, observedAt: Int64) {
        guard let html = String(data: data, encoding: .utf8),
              currency(in: html) == "USD",
              let (price, observed) = priceAndTime(in: html, now: now),
              price > 0.5, price < 2.0 else { throw WallstreetOnlineQuoteError.invalidFX }
        return (price, observed)
    }

    static func decode(_ data: Data, instrumentID: String,
                       euroUSD: (rate: Double, observedAt: Int64)?, now: Date) throws -> WallstreetOnlineQuote {
        guard let html = String(data: data, encoding: .utf8),
              let currency = currency(in: html),
              let (price, observed) = priceAndTime(in: html, now: now) else {
            throw WallstreetOnlineQuoteError.invalidPage
        }
        let priceEUR: Double
        let rate: Double?
        let fxObservedAt: Int64?
        switch currency {
        case "EUR":
            priceEUR = price
            rate = nil
            fxObservedAt = nil
        case "USD":
            guard let euroUSD, abs(euroUSD.observedAt - observed) <= 5 * 60_000 else {
                throw WallstreetOnlineQuoteError.invalidFX
            }
            priceEUR = price / euroUSD.rate
            rate = euroUSD.rate
            fxObservedAt = euroUSD.observedAt
        default:
            throw WallstreetOnlineQuoteError.unsupportedCurrency
        }
        guard priceEUR.isFinite, priceEUR > 0 else { throw WallstreetOnlineQuoteError.invalidPage }
        return WallstreetOnlineQuote(instrumentID: instrumentID, priceEUR: priceEUR,
                                     sourceCurrency: currency, sourcePrice: price,
                                     euroUSDRate: rate, fxObservedAtMillis: fxObservedAt,
                                     observedAtMillis: observed)
    }

    private static func currency(in html: String) -> String? {
        guard let block = MarketPageHTML.first("<div class=\"marketchange\"[^>]*>(.*?)<div class=\"float-start askbidBox", in: html) else {
            return nil
        }
        return MarketPageHTML.first("<div table=\"quotes\" class=\"quote_currency\">([A-Z]{3})</div>", in: block)
    }

    private static func priceAndTime(in html: String, now: Date) -> (Double, Int64)? {
        guard let block = MarketPageHTML.first("<div class=\"marketchange\"[^>]*>(.*?)<div class=\"float-start askbidBox", in: html),
              let priceText = MarketPageHTML.first("<div class=\"float-start quoteValue\"><span[^>]*>(.*?)</span>", in: block),
              let timeText = MarketPageHTML.first("data-push=\";ls;quotes;[^\"]+;tt\"[^>]*>(.*?)</span>", in: block),
              let price = MarketPageHTML.germanNumber(priceText),
              let observed = MarketPageHTML.quoteTime(MarketPageHTML.plainText(timeText), now: now) else {
            return nil
        }
        return (price, observed)
    }
}

enum WallstreetOnlineQuoteError: LocalizedError {
    case invalidPage, invalidFX, unsupportedCurrency

    var errorDescription: String? {
        switch self {
        case .invalidPage: "wallstreetONLINE did not provide a fresh quote."
        case .invalidFX: "A fresh EUR/USD quote is required for a USD price."
        case .unsupportedCurrency: "The quote currency cannot be converted to EUR."
        }
    }
}
