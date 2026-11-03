import Foundation

struct FMPExchangeRate: Sendable {
    let eurosToDollars: Double
    let observedAtMillis: Int64

    func isUsable(for signal: ScanResult, nowMillis: Int64) -> Bool {
        let maximumDifference: Int64 = 20 * 60 * 1_000
        return nowMillis >= observedAtMillis && nowMillis - observedAtMillis <= maximumDifference &&
            abs(signal.signalEpochMillis - observedAtMillis) <= maximumDifference
    }
}

struct FMPExchangeRateSource: Sendable {
    private let session: URLSession

    init(session: URLSession = .shared) { self.session = session }

    func loadEURUSD(apiKey: String, nowMillis: Int64) async throws -> FMPExchangeRate {
        var components = URLComponents(string: "https://financialmodelingprep.com/stable/quote")!
        components.queryItems = [
            URLQueryItem(name: "symbol", value: "EURUSD"),
            URLQueryItem(name: "apikey", value: apiKey)
        ]
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 10
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw FMPExchangeRateError.invalidResponse }
        guard http.statusCode == 200 else { throw FMPExchangeRateError.httpStatus(http.statusCode) }
        guard data.count <= 100_000 else { throw FMPExchangeRateError.invalidResponse }
        return try Self.decode(data, nowMillis: nowMillis)
    }

    static func decode(_ data: Data, nowMillis: Int64) throws -> FMPExchangeRate {
        guard let rows = try? JSONDecoder().decode([Quote].self, from: data),
              let quote = rows.first(where: { $0.symbol == "EURUSD" }),
              quote.price.isFinite, quote.price > 0,
              quote.timestamp > 0 else { throw FMPExchangeRateError.invalidResponse }
        let observedAtMillis = quote.timestamp * 1_000
        guard observedAtMillis <= nowMillis + 60_000,
              nowMillis - observedAtMillis <= 20 * 60 * 1_000 else {
            throw FMPExchangeRateError.stale
        }
        return FMPExchangeRate(eurosToDollars: quote.price, observedAtMillis: observedAtMillis)
    }

    private struct Quote: Decodable {
        let symbol: String
        let price: Double
        let timestamp: Int64
    }
}

enum FMPExchangeRateError: Error {
    case invalidResponse, stale, httpStatus(Int)
}
