import Foundation

actor RadarCompanyMetadataService {
    private let session: URLSession
    private let cacheLifetime: Int64 = 7 * 24 * 60 * 60 * 1_000
    private let incompleteCacheLifetime: Int64 = 15 * 60 * 1_000

    init(session: URLSession = .shared) { self.session = session }

    func cached(symbols: [String]) async -> [String: RadarCompanyMetadata] {
        guard let store = try? RadarCompanyMetadataStore(url: RadarCompanyMetadataStore.defaultURL()) else { return [:] }
        return (try? await store.load(symbols: Self.normalized(symbols))) ?? [:]
    }

    func load(symbols: [String], names: [String: String]) async -> [String: RadarCompanyMetadata] {
        do {
            let store = try RadarCompanyMetadataStore(url: RadarCompanyMetadataStore.defaultURL())
            let normalized = Self.normalized(symbols)
            var metadata = try await store.load(symbols: Array(normalized))
            let now = Int64(Date().timeIntervalSince1970 * 1_000)
            let stale = normalized.filter { symbol in
                guard let cached = metadata[symbol] else { return true }
                let lifetime = cached.logoData == nil || cached.countryCode == nil
                    ? incompleteCacheLifetime : cacheLifetime
                return now - cached.updatedAtMillis > lifetime
            }
            let fmpKey = MarketProviderAccess.isOperational(.fmp)
                ? try? ProviderCredentialStore.load(FMPCredential.account) : nil
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
                            let name = providerProfile?.name ?? fallbackName
                            let country = providerProfile?.countryCode ?? cached?.countryCode
                            var image = await Self.loadLogo(providerProfile?.logoURL, session: requestSession)
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

    private static func normalized(_ symbols: [String]) -> [String] {
        var seen = Set<String>()
        return Array(symbols.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
            .filter { !$0.isEmpty && seen.insert($0).inserted }.prefix(101))
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


}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
