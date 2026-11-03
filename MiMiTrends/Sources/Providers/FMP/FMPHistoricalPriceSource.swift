import Foundation

struct FMPHistoricalPriceSource: Sendable {
    private let session: URLSession

    init(session: URLSession = .shared) { self.session = session }

    func dailyBars(symbol: String, apiKey: String, through date: Date = .now) async throws -> [MinuteBar] {
        guard FinnhubBidAskClient.supports(symbol: symbol) else { throw FMPHistoryError.invalidSymbol }
        var components = URLComponents(string: "https://financialmodelingprep.com/stable/historical-price-eod/full")!
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        components.queryItems = [
            URLQueryItem(name: "symbol", value: symbol),
            URLQueryItem(name: "from", value: formatter.string(from: date.addingTimeInterval(-370 * 86_400))),
            URLQueryItem(name: "to", value: formatter.string(from: date)),
            URLQueryItem(name: "apikey", value: apiKey)
        ]
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw FMPHistoryError.invalidResponse }
        guard http.statusCode == 200 else { throw FMPHistoryError.httpStatus(http.statusCode) }
        guard data.count <= 2_000_000 else { throw FMPHistoryError.invalidResponse }
        return try Self.decode(data, symbol: symbol)
    }

    static func decode(_ data: Data, symbol: String) throws -> [MinuteBar] {
        guard let rows = try? JSONDecoder().decode([Row].self, from: data) else {
            throw FMPHistoryError.invalidResponse
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let bars = rows.compactMap { row -> MinuteBar? in
            guard row.symbol == symbol,
                  let day = calendar.date(from: DateComponents(year: row.year, month: row.month, day: row.day, hour: 12)) else {
                return nil
            }
            let bar = MinuteBar(
                symbol: symbol, minuteEpochSeconds: Int64(day.timeIntervalSince1970),
                open: row.open, high: row.high, low: row.low, close: row.close,
                volume: row.volume, volumeStatus: row.volume > 0 ? .reported : .zero
            )
            return bar.isValid ? bar : nil
        }
        guard bars.count == rows.count else { throw FMPHistoryError.invalidResponse }
        return bars.sorted { $0.minuteEpochSeconds < $1.minuteEpochSeconds }
    }

    private struct Row: Decodable {
        let symbol: String
        let open: Double
        let high: Double
        let low: Double
        let close: Double
        let volume: Double
        private let date: String

        var year: Int { Int(date.prefix(4)) ?? 0 }
        var month: Int { Int(date.dropFirst(5).prefix(2)) ?? 0 }
        var day: Int { Int(date.suffix(2)) ?? 0 }
    }
}

enum FMPHistoryError: LocalizedError {
    case invalidSymbol, invalidResponse, httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .invalidSymbol: "This symbol is not supported for historical prices."
        case .invalidResponse: "FMP did not return valid daily prices."
        case .httpStatus(let status): "FMP historical prices are unavailable (HTTP \(status)). Check plan access in Settings."
        }
    }
}
