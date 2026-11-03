import Foundation

actor RadarCompanyMetadataService {
    private let session: URLSession
    private let cacheLifetime: Int64 = 7 * 24 * 60 * 60 * 1_000

    init(session: URLSession = .shared) { self.session = session }

    func load(symbols: [String], names: [String: String]) async -> [String: RadarCompanyMetadata] {
        do {
            let store = try RadarCompanyMetadataStore(url: RadarCompanyMetadataStore.defaultURL())
            var seen = Set<String>()
            let normalized = symbols.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
                .filter { !$0.isEmpty && seen.insert($0).inserted }.prefix(30)
            var metadata = try await store.load(symbols: Array(normalized))
            let now = Int64(Date().timeIntervalSince1970 * 1_000)
            let stale = normalized.filter { symbol in
                guard let cached = metadata[symbol] else { return true }
                return now - cached.updatedAtMillis > cacheLifetime
            }
            let token = try? FinnhubCredentialStore.load()
            let fmpKey = try? ProviderCredentialStore.load(FMPCredential.account)
            let requestSession = session
            let fmp = FMPCompanyProfileSource(session: requestSession)
            for offset in stride(from: 0, to: stale.count, by: 4) {
                let batch = Array(stale[offset..<min(offset + 4, stale.count)])
                await withTaskGroup(of: (String, RadarCompanyMetadata?).self) { group in
                    for symbol in batch {
                        let fallbackName = names[symbol] ?? metadata[symbol]?.name ?? symbol
                        let cached = metadata[symbol]
                        group.addTask {
                            guard !Task.isCancelled else { return (symbol, nil) }
                            let providerProfile: FMPCompanyProfile?
                            if let fmpKey { providerProfile = await fmp.profile(symbol: symbol, apiKey: fmpKey) }
                            else { providerProfile = nil }
                            let providerImage = await Self.loadLogo(providerProfile?.logoURL, session: requestSession)
                            let finnhubProfile: CompanyProfileResponse?
                            if providerImage == nil {
                                finnhubProfile = await Self.fetchProfile(symbol: symbol, apiKey: token, session: requestSession)
                            } else {
                                finnhubProfile = nil
                            }
                            let name = providerProfile?.name ?? finnhubProfile?.profileName ?? fallbackName
                            let country = providerProfile?.countryCode ?? finnhubProfile?.countryCode
                                ?? cached?.countryCode ?? RadarCompanyMetadata.countryFallback(for: symbol)
                            let finnhubLogo = finnhubProfile?.logoURL.flatMap { URL(string: $0) }
                            var image = providerImage
                            if image == nil { image = await Self.loadLogo(finnhubLogo, session: requestSession) }
                            if image == nil { image = cached?.logoData }
                            if image == nil { image = await Self.loadCompanyMark(name: name, session: requestSession) }
                            return (symbol, RadarCompanyMetadata(
                                symbol: symbol, name: name, countryCode: country,
                                logoData: image, updatedAtMillis: now
                            ))
                        }
                    }
                    for await (symbol, value) in group {
                        guard let value else { continue }
                        try? await store.save(value)
                        metadata[symbol] = value
                    }
                }
            }
            return metadata
        } catch {
            AppDiagnostics.shared.record(.warning, "Radar", "company-metadata-cache-failed",
                                         "error=\(String(describing: type(of: error)))")
            return [:]
        }
    }

    private static func fetchProfile(symbol: String, apiKey: String?, session: URLSession) async -> CompanyProfileResponse? {
        guard let apiKey, !apiKey.isEmpty,
              var components = URLComponents(string: "https://finnhub.io/api/v1/stock/profile2") else { return nil }
        components.queryItems = [URLQueryItem(name: "symbol", value: symbol)]
        guard let url = components.url else { return nil }
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "X-Finnhub-Token")
        request.timeoutInterval = 10
        do {
            let (data, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200, data.count <= 100_000 else { return nil }
            return try JSONDecoder().decode(CompanyProfileResponse.self, from: data)
        } catch { return nil }
    }

    private static func loadLogo(_ url: URL?, session: URLSession) async -> Data? {
        guard let url else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        do {
            let (data, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  !data.isEmpty, data.count <= 512_000 else { return nil }
            return data
        } catch { return nil }
    }

    private static func loadCompanyMark(name: String, session: URLSession) async -> Data? {
        guard var components = URLComponents(string: "https://api.loadlogo.com/search") else { return nil }
        components.queryItems = [URLQueryItem(name: "q", value: name)]
        guard let url = components.url else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("MiMiTrends/1.0", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  data.count <= 1_000_000,
                  let results = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                  let domain = Self.bestDomain(in: results, companyName: name),
                  let iconURL = URL(string: "https://www.google.com/s2/favicons?domain=\(domain)&sz=64") else { return nil }
            return await loadLogo(iconURL, session: session)
        } catch { return nil }
    }

    private static func bestDomain(in results: [[String: Any]], companyName: String) -> String? {
        let target = tokens(companyName)
        return results.compactMap { result -> (String, Double)? in
            guard let raw = result["domain"] as? String else { return nil }
            let domain = raw.lowercased().replacingOccurrences(of: "https://", with: "")
                .replacingOccurrences(of: "http://", with: "").components(separatedBy: "/").first ?? ""
            guard domain.range(of: #"^[a-z0-9](?:[a-z0-9.-]*[a-z0-9])?\.[a-z]{2,}$"#, options: .regularExpression) != nil else { return nil }
            let candidate = tokens(result["name"] as? String ?? domain)
            let score = Double(target.intersection(candidate).count) / Double(max(1, target.union(candidate).count))
            return (domain, score)
        }.max(by: { $0.1 < $1.1 }).flatMap { $0.1 >= 0.5 ? $0.0 : nil }
    }

    private static func tokens(_ value: String) -> Set<String> {
        Set(value.lowercased().split { !$0.isLetter && !$0.isNumber }
            .map(String.init).filter { $0.count > 1 && !legalSuffixes.contains($0) })
    }

    private static let legalSuffixes: Set<String> = ["inc", "incorporated", "corp", "corporation", "company", "co", "ltd", "plc", "ag", "se", "sa", "spa", "gmbh", "group"]

    private struct CompanyProfileResponse: Decodable {
        let name: String?
        let country: String?
        let logo: String?

        var profileName: String? { name?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty }
        var countryCode: String? { country?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty }
        var logoURL: String? { logo?.hasPrefix("https://") == true ? logo : nil }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
