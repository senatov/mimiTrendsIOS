import Foundation

enum FinnhubTradeDecoder {
    static func decode(_ data: Data) throws -> [TradeTick] {
        let envelope: Envelope
        do {
            envelope = try JSONDecoder().decode(Envelope.self, from: data)
        } catch {
            throw FinnhubStreamError.invalidMessage
        }

        if envelope.type == "error" {
            throw FinnhubStreamError.providerRejected
        }
        guard envelope.type == "trade" else { return [] }
        guard let items = envelope.data else { throw FinnhubStreamError.invalidMessage }

        return items.compactMap { item in
            guard let symbol = item.s, !symbol.isEmpty,
                  let price = item.p, price.isFinite else { return nil }
            return TradeTick(
                symbol: symbol,
                price: price,
                timestampMillis: item.t ?? 0,
                volume: item.v ?? 0
            )
        }
    }

    private struct Envelope: Decodable {
        let type: String
        let data: [Trade]?
    }

    private struct Trade: Decodable {
        let s: String?
        let p: Double?
        let t: Int64?
        let v: Double?
    }
}

enum FinnhubStreamError: LocalizedError {
    case missingKey
    case invalidMessage
    case providerRejected
    case connectionFailed(String)
    case invalidSubscription

    var errorDescription: String? {
        switch self {
        case .missingKey: "Enter a Finnhub API key in Settings."
        case .invalidMessage: "Finnhub sent an unreadable trade message."
        case .providerRejected: "Finnhub rejected the stream request. Check the API key and plan."
        case .connectionFailed(let reason): "Could not connect to Finnhub. \(reason)"
        case .invalidSubscription: "Choose one to five valid symbols for the Finnhub feed."
        }
    }
}
