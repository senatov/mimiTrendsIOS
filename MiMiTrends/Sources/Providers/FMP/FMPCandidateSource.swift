import Foundation

enum FMPCredential {
    static let account = "financial-modeling-prep"
}

struct FMPCandidateSource: Sendable {
    private let session: URLSession
    private let baseURL = URL(string: "https://financialmodelingprep.com/stable/")!
    private let paths = ["most-actives", "biggest-gainers", "biggest-losers"]

    init(session: URLSession = .shared) { self.session = session }

    func activeCandidates(apiKey: String, limit: Int = 40) async throws -> [RadarCompanyCandidate] {
        var lists: [[RadarCompanyCandidate]] = []
        var requests = 0
        do {
            for path in paths {
                try Task.checkCancellation()
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
            throw FMPCandidateFailure(requests: requests, reason: String(describing: error))
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
                  price.isFinite, price > 0 else { return nil }
            let symbol = rawSymbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, FinnhubBidAskClient.supports(symbol: symbol),
                  (row["exchange"] as? String)?.uppercased() != "OTC" else { return nil }
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
}

enum FMPCandidateError: Error {
    case invalidResponse
    case httpStatus(Int)
}

struct FMPCandidateFailure: Error, Sendable {
    let requests: Int
    let reason: String
}
