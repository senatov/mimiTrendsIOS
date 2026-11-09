import Foundation

struct FinnhubTradeStream: Sendable {
    func checkConnection(apiKey: String, symbol: String, endpointURL: URL? = nil) async throws {
        let url = try Self.streamURL(apiKey: apiKey, endpointURL: endpointURL)
        let command = try Self.subscriptionMessages(for: [symbol])[0]
        let socket = URLSession.shared.webSocketTask(with: url)
        let deadline = FinnhubConnectionCheckDeadline()
        socket.resume()
        defer { socket.cancel(with: .normalClosure, reason: nil) }

        try await socket.send(.string(command))
        let timeout = Task {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            await deadline.expire()
            socket.cancel(with: .goingAway, reason: nil)
        }
        defer { timeout.cancel() }

        do {
            let message = try await socket.receive()
            timeout.cancel()
            let data: Data
            switch message {
            case .data(let payload): data = payload
            case .string(let text): data = Data(text.utf8)
            @unknown default: throw FinnhubStreamError.invalidMessage
            }
            _ = try FinnhubTradeDecoder.decode(data)
        } catch {
            if await deadline.didExpire() { return }
            throw error
        }
    }

    func run(
        apiKey: String,
        symbols: [String],
        onSubscribed: @escaping @Sendable () async -> Void,
        onTrade: @escaping @Sendable (TradeTick) async throws -> Void
    ) async throws {
        let url = try Self.streamURL(apiKey: apiKey)
        let commands = try Self.subscriptionMessages(for: symbols)
        let subscribedSymbols = Set(symbols)

        let socket = URLSession.shared.webSocketTask(with: url)
        try await withTaskCancellationHandler {
            socket.resume()
            defer { socket.cancel(with: .normalClosure, reason: nil) }
            do {
                for command in commands {
                    try Task.checkCancellation()
                    try await socket.send(.string(command))
                }
                try Task.checkCancellation()
                await onSubscribed()
                while !Task.isCancelled {
                    let message = try await socket.receive()
                    let data: Data
                    switch message {
                    case .data(let payload): data = payload
                    case .string(let text): data = Data(text.utf8)
                    @unknown default: throw FinnhubStreamError.invalidMessage
                    }
                    for trade in try FinnhubTradeDecoder.decode(data) {
                        try Task.checkCancellation()
                        let normalizedSymbol = trade.symbol.uppercased()
                        guard subscribedSymbols.contains(normalizedSymbol) else { continue }
                        try await onTrade(TradeTick(
                            symbol: normalizedSymbol,
                            price: trade.price,
                            timestampMillis: trade.timestampMillis,
                            volume: trade.volume
                        ))
                    }
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as FinnhubStreamError {
                if Task.isCancelled { throw CancellationError() }
                throw error
            } catch let error as MarketBarStoreError {
                if Task.isCancelled { throw CancellationError() }
                throw error
            } catch let error as MarketSignalStoreError {
                if Task.isCancelled { throw CancellationError() }
                throw error
            } catch {
                if Task.isCancelled { throw CancellationError() }
                throw FinnhubStreamError.connectionFailed(Self.connectionFailureReason(error))
            }
        } onCancel: {
            socket.cancel(with: .normalClosure, reason: nil)
        }
    }

    static func streamURL(apiKey: String, endpointURL: URL? = nil) throws -> URL {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw FinnhubStreamError.missingKey }
        guard var components = URLComponents(url: endpointURL ?? ProviderEndpointStore.url(for: .finnhubTrades),
                                             resolvingAgainstBaseURL: false) else {
            throw FinnhubStreamError.missingKey
        }
        components.queryItems = [URLQueryItem(name: "token", value: key)]
        guard let url = components.url else { throw FinnhubStreamError.missingKey }
        return url
    }

    static func subscriptionMessages(for symbols: [String]) throws -> [String] {
        guard (1...FinnhubWatchlistSelection.maximumSymbols).contains(symbols.count),
              Set(symbols).count == symbols.count,
              symbols.allSatisfy({ (try? WatchlistStore.normalize($0)) == $0 }) else {
            throw FinnhubStreamError.invalidSubscription
        }
        return try symbols.map { symbol in
            let data = try JSONEncoder().encode(Subscription(type: "subscribe", symbol: symbol))
            guard let text = String(data: data, encoding: .utf8) else {
                throw FinnhubStreamError.invalidSubscription
            }
            return text
        }
    }

    private static func connectionFailureReason(_ error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut:
                return "The connection timed out. Check the network and try again."
            case .notConnectedToInternet, .networkConnectionLost:
                return "The device has no stable internet connection. Check the network and try again."
            case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
                return "The device could not reach Finnhub. Check the network or DNS settings."
            case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate,
                 .serverCertificateNotYetValid:
                return "A secure connection to Finnhub could not be verified. Check the device date and network security settings."
            case .badServerResponse, .cannotParseResponse:
                return "Finnhub did not accept the WebSocket handshake. Check the Finnhub endpoint and account access."
            default:
                return "Network connection error (\(urlError.code.rawValue)). Check the endpoint, network, and Finnhub account access."
            }
        }
        let socketError = error as NSError
        return "Socket error \(socketError.code). Check the endpoint, network, and Finnhub account access."
    }

    private struct Subscription: Encodable {
        let type: String
        let symbol: String
    }
}

private actor FinnhubConnectionCheckDeadline {
    private var expired = false

    func expire() { expired = true }
    func didExpire() -> Bool { expired }
}
