import Foundation

struct FinnhubTradeStream: Sendable {
    func checkConnection(apiKey: String, symbol: String, endpointURL: URL? = nil) async throws {
        let url = try Self.streamURL(apiKey: apiKey, endpointURL: endpointURL)
        let command = try Self.subscriptionMessages(for: [symbol])[0]
        let socket = URLSession.shared.webSocketTask(with: url)
        let deadline = FinnhubConnectionCheckDeadline()
        let host = url.host ?? "unknown"
        AppDiagnostics.shared.record(.info, "Finnhub", "connection-check-start", "host=\(host) symbol=\(symbol)")
        socket.resume()
        defer { socket.cancel(with: .normalClosure, reason: nil) }

        try await socket.send(.string(command))
        AppDiagnostics.shared.record(.info, "Finnhub", "connection-check-subscription-sent", "symbol=\(symbol)")
        let timeout = Task {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            await deadline.expire()
            AppDiagnostics.shared.record(.warning, "Finnhub", "connection-check-no-frame",
                                         "symbol=\(symbol) result=socket-open-but-no-data-frame-within-5s")
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
            let type = FinnhubTradeDecoder.messageType(data)
            let trades = try FinnhubTradeDecoder.decode(data)
            AppDiagnostics.shared.record(.info, "Finnhub", "connection-check-frame",
                                         "symbol=\(symbol) type=\(type) decodedTrades=\(trades.count)")
        } catch {
            if await deadline.didExpire() {
                AppDiagnostics.shared.record(.info, "Finnhub", "connection-check-result",
                                             "symbol=\(symbol) transport=reachable data=not-confirmed")
                return
            }
            AppDiagnostics.shared.record(.error, "Finnhub", "connection-check-failed",
                                         Self.safeErrorDetails(error))
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
        let host = url.host ?? "unknown"
        let telemetry = FinnhubStreamTelemetry()
        AppDiagnostics.shared.record(.info, "Finnhub", "stream-start", "host=\(host) symbols=\(symbols.joined(separator: ","))")
        try await withTaskCancellationHandler {
            socket.resume()
            defer { socket.cancel(with: .normalClosure, reason: nil) }
            let waitingMonitor = Task {
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(30)) } catch { return }
                    guard !Task.isCancelled else { return }
                    let stats = await telemetry.snapshot()
                    AppDiagnostics.shared.record(.warning, "Finnhub", "stream-still-waiting",
                        "symbols=\(symbols.joined(separator: ",")) frames=\(stats.frames) trades=\(stats.trades) elapsedSeconds=\(stats.elapsedSeconds)")
                }
            }
            defer { waitingMonitor.cancel() }
            do {
                for command in commands {
                    try Task.checkCancellation()
                    try await socket.send(.string(command))
                }
                try Task.checkCancellation()
                AppDiagnostics.shared.record(.info, "Finnhub", "stream-subscriptions-sent",
                                             "count=\(commands.count) symbols=\(symbols.joined(separator: ","))")
                await onSubscribed()
                while !Task.isCancelled {
                    let message = try await socket.receive()
                    let data: Data
                    switch message {
                    case .data(let payload): data = payload
                    case .string(let text): data = Data(text.utf8)
                    @unknown default: throw FinnhubStreamError.invalidMessage
                    }
                    let frameNumber = await telemetry.recordFrame()
                    let messageType = FinnhubTradeDecoder.messageType(data)
                    let decodedTrades: [TradeTick]
                    do {
                        decodedTrades = try FinnhubTradeDecoder.decode(data)
                    } catch {
                        AppDiagnostics.shared.record(.error, "Finnhub", "stream-frame-rejected",
                            "frame=\(frameNumber) type=\(messageType) bytes=\(data.count) error=\(Self.safeErrorDetails(error))")
                        throw error
                    }
                    let accepted = decodedTrades.filter { subscribedSymbols.contains($0.symbol.uppercased()) }
                    if frameNumber == 1 || messageType == "error" || !accepted.isEmpty {
                        AppDiagnostics.shared.record(messageType == "error" ? .error : .info, "Finnhub", "stream-frame",
                            "frame=\(frameNumber) type=\(messageType) bytes=\(data.count) decodedTrades=\(decodedTrades.count) subscribedTrades=\(accepted.count)")
                    }
                    for trade in decodedTrades {
                        try Task.checkCancellation()
                        let normalizedSymbol = trade.symbol.uppercased()
                        guard subscribedSymbols.contains(normalizedSymbol) else { continue }
                        await telemetry.recordTrade()
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
                AppDiagnostics.shared.record(.error, "Finnhub", "stream-provider-error",
                                             "errorType=\(String(describing: type(of: error)))")
                throw error
            } catch let error as MarketBarStoreError {
                if Task.isCancelled { throw CancellationError() }
                AppDiagnostics.shared.record(.error, "Finnhub", "stream-bar-store-error",
                                             "errorType=\(String(describing: type(of: error)))")
                throw error
            } catch let error as MarketSignalStoreError {
                if Task.isCancelled { throw CancellationError() }
                AppDiagnostics.shared.record(.error, "Finnhub", "stream-signal-store-error",
                                             "errorType=\(String(describing: type(of: error)))")
                throw error
            } catch {
                if Task.isCancelled { throw CancellationError() }
                AppDiagnostics.shared.record(.error, "Finnhub", "stream-failed", Self.safeErrorDetails(error))
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

    private static func safeErrorDetails(_ error: Error) -> String {
        let nsError = error as NSError
        return "errorType=\(String(describing: type(of: error))) domain=\(nsError.domain) code=\(nsError.code)"
    }

    private struct Subscription: Encodable {
        let type: String
        let symbol: String
    }
}

private actor FinnhubStreamTelemetry {
    private let startedAt = Date()
    private var frames = 0
    private var trades = 0

    func recordFrame() -> Int {
        frames += 1
        return frames
    }

    func recordTrade() { trades += 1 }

    func snapshot() -> (frames: Int, trades: Int, elapsedSeconds: Int) {
        (frames, trades, Int(Date().timeIntervalSince(startedAt)))
    }
}

private actor FinnhubConnectionCheckDeadline {
    private var expired = false

    func expire() { expired = true }
    func didExpire() -> Bool { expired }
}
