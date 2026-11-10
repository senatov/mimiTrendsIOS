import Foundation

enum FMPCredential {
    static let account = "financial-modeling-prep"
}

struct FMPCandidateSource: Sendable {
    private let session: URLSession
    private let baseURL = URL(string: "https://financialmodelingprep.com/stable/")!
    private let paths = ["most-actives", "biggest-gainers", "biggest-losers"]

    init(session: URLSession = .shared) { self.session = session }

    func check(apiKey: String) async throws {
        var components = URLComponents(url: baseURL.appendingPathComponent("most-actives"),
                                       resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "apikey", value: apiKey)]
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 12
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw FMPCandidateError.invalidResponse }
        guard http.statusCode == 200 else { throw FMPCandidateError.httpStatus(http.statusCode) }
        guard data.count <= 2_000_000,
              (try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]) != nil else {
            throw FMPCandidateError.invalidResponse
        }
    }

    func activeCandidates(apiKey: String, limit: Int = 40) async throws -> [RadarCompanyCandidate] {
        var lists: [[RadarCompanyCandidate]] = []
        var requests = 0
        var activePath = "unknown"
        do {
            for path in paths {
                try Task.checkCancellation()
                activePath = path
                var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
                components.queryItems = [URLQueryItem(name: "apikey", value: apiKey)]
                var request = URLRequest(url: components.url!)
                request.timeoutInterval = 15
                request.cachePolicy = .reloadIgnoringLocalCacheData
                request.setValue("application/json", forHTTPHeaderField: "Accept")
                requests += 1
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    throw FMPCandidateError.invalidResponse
                }
                guard http.statusCode == 200 else { throw FMPCandidateError.httpStatus(http.statusCode) }
                guard data.count <= 2_000_000 else { throw FMPCandidateError.invalidResponse }
                lists.append(try Self.decodeCandidates(data))
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw FMPCandidateFailure(requests: requests, endpoint: activePath,
                                      reason: Self.describe(error))
        }
        return Self.interleave(lists, limit: limit)
    }

    static func decodeCandidates(_ data: Data) throws -> [RadarCompanyCandidate] {
        guard let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw FMPCandidateError.invalidResponse
        }
        return rows.compactMap { row in
            guard let rawSymbol = row["symbol"] as? String,
                  let rawName = row["name"] as? String,
                  let price = (row["price"] as? NSNumber)?.doubleValue,
                  let exchange = row["exchange"] as? String else { return nil }
            let symbol = rawSymbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard row["isEtf"] as? Bool != true,
                  row["isFund"] as? Bool != true,
                  MarketCandidateFilter.accepts(
                    symbol: symbol, name: name, price: price, exchange: exchange,
                    currency: row["currency"] as? String,
                    volume: (row["volume"] as? NSNumber)?.doubleValue,
                    marketCap: (row["marketCap"] as? NSNumber)?.doubleValue
                  ) else { return nil }
            return RadarCompanyCandidate(symbol: symbol, name: name)
        }
    }

    static func interleave(_ lists: [[RadarCompanyCandidate]], limit: Int) -> [RadarCompanyCandidate] {
        guard limit > 0 else { return [] }
        var result: [RadarCompanyCandidate] = []
        var seen = Set<String>()
        for index in 0..<(lists.map(\.count).max() ?? 0) {
            for list in lists where index < list.count {
                let candidate = list[index]
                if seen.insert(candidate.symbol).inserted { result.append(candidate) }
                if result.count >= limit { return result }
            }
        }
        return result
    }

    private static func describe(_ error: Error) -> String {
        if let failure = error as? FMPCandidateError {
            switch failure {
            case .invalidResponse: return "FMP returned an unexpected response or JSON format."
            case .httpStatus(let status):
                switch status {
                case 401, 403: return "FMP rejected the API key or this endpoint is not available on the account (HTTP \(status))."
                case 402: return "FMP plan or request limit blocked this endpoint (HTTP 402)."
                case 429: return "FMP rate limit reached (HTTP 429)."
                default: return "FMP returned HTTP \(status)."
                }
            }
        }
        if let error = error as? URLError {
            switch error.code {
            case .timedOut: return "The FMP request timed out."
            case .notConnectedToInternet, .networkConnectionLost: return "The device could not reach FMP."
            default: return "FMP network request failed: \(error.localizedDescription)"
            }
        }
        return "FMP candidate response could not be read: \(String(describing: error))"
    }
}

enum FMPCandidateError: LocalizedError {
    case invalidResponse
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "FMP returned an unexpected response or JSON format."
        case .httpStatus(let status):
            switch status {
            case 401, 403: "FMP rejected the API key or this endpoint is not available on the account (HTTP \(status))."
            case 402: "FMP plan or request limit blocked this endpoint (HTTP 402)."
            case 429: "FMP request limit reached (HTTP 429). Check account usage and plan access in your FMP dashboard."
            default: "FMP returned HTTP \(status)."
            }
        }
    }
}

struct FMPCandidateFailure: Error, Sendable {
    let requests: Int
    let endpoint: String
    let reason: String

    var localizedDescription: String { "\(reason) Endpoint: \(endpoint)." }
}
