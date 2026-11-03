import Foundation

struct FMPCompanyProfile: Sendable {
    let name: String?
    let countryCode: String?
    let logoURL: URL?
}

struct FMPCompanyProfileSource: Sendable {
    private let session: URLSession

    init(session: URLSession = .shared) { self.session = session }

    func profile(symbol: String, apiKey: String) async -> FMPCompanyProfile? {
        guard var components = URLComponents(string: "https://financialmodelingprep.com/stable/profile") else {
            return nil
        }
        components.queryItems = [
            URLQueryItem(name: "symbol", value: symbol),
            URLQueryItem(name: "apikey", value: apiKey)
        ]
        guard let url = components.url else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  data.count <= 100_000 else { return nil }
            return Self.decode(data, symbol: symbol)
        } catch { return nil }
    }

    static func decode(_ data: Data, symbol: String) -> FMPCompanyProfile? {
        guard let rows = try? JSONDecoder().decode([Response].self, from: data),
              let row = rows.first(where: { $0.symbol.caseInsensitiveCompare(symbol) == .orderedSame }) else {
            return nil
        }
        let logoURL = row.defaultImage == true ? nil : row.image.flatMap { URL(string: $0) }
        let trustedLogo = logoURL.flatMap { url in
            url.scheme == "https" && url.host == "images.financialmodelingprep.com" ? url : nil
        }
        return FMPCompanyProfile(
            name: row.companyName.flatMap { cleaned($0) },
            countryCode: row.country.flatMap { cleaned($0) },
            logoURL: trustedLogo
        )
    }

    private static func cleaned(_ value: String) -> String? {
        let result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : result
    }

    private struct Response: Decodable {
        let symbol: String
        let companyName: String?
        let country: String?
        let image: String?
        let defaultImage: Bool?
    }
}
