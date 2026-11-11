import Foundation

struct RadarCoverageRequest: Identifiable, Sendable {
    let symbol: String
    let companyName: String
    var id: String { symbol }
}

struct CoverageItem: Identifiable, Sendable {
    let title: String
    let publisher: String
    let url: URL
    let publishedAt: Date?
    let publishedLabel: String?

    var id: String { url.absoluteString.components(separatedBy: "?").first ?? url.absoluteString }
}

struct CoverageResult: Sendable {
    let items: [CoverageItem]
    let unavailableSources: [String]
}

struct RecentCoverageClient: Sendable {
    private let session: URLSession

    init(session: URLSession = .shared) { self.session = session }

    func load(symbol: String, companyName: String) async -> CoverageResult {
        async let yahoo = capture("Yahoo Finance") { try await yahooNews(symbol: symbol, companyName: companyName) }
        async let benzinga = capture("Benzinga") { try await benzingaNews(symbol: symbol, companyName: companyName) }
        async let wallstreet = capture("wallstreetONLINE") { try await wallstreetOnlineNews(symbol: symbol, companyName: companyName) }
        let sources = await [yahoo, benzinga, wallstreet]
        let items = Self.displayItems(sources.flatMap(\.items))
        return CoverageResult(items: items, unavailableSources: sources.compactMap(\.unavailable))
    }

    static func displayItems(_ items: [CoverageItem]) -> [CoverageItem] {
        var links = Set<String>()
        var titles = Set<String>()
        let unique = items.filter { item in
            let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !links.contains(item.id), !titles.contains(title) else { return false }
            links.insert(item.id)
            titles.insert(title)
            return true
        }
        return unique.sorted { ($0.publishedAt ?? .distantPast) > ($1.publishedAt ?? .distantPast) }
    }

    private func capture(
        _ name: String, operation: @Sendable () async throws -> [CoverageItem]
    ) async -> SourceResult {
        do { return SourceResult(items: try await operation(), unavailable: nil) }
        catch {
            AppDiagnostics.shared.record(.warning, name, "recent-coverage-failed", "error=\(String(describing: type(of: error)))")
            return SourceResult(items: [], unavailable: name)
        }
    }

    private func yahooNews(symbol: String, companyName: String) async throws -> [CoverageItem] {
        let feedItems = try? await yahooFeed(symbol: symbol)
        let tickerItems = try? await yahooSearch(symbol)
        let ticker = tickerItems ?? []
        let name = searchName(companyName)
        if ticker.count >= 5 || name.caseInsensitiveCompare(symbol) == .orderedSame {
            if feedItems != nil || tickerItems != nil { return ticker + (feedItems ?? []) }
            throw CoverageClientError.unavailable
        }
        let nameItems = try? await yahooSearch(name).filter { matchesCompany($0.title, symbol: symbol, companyName: name) }
        if feedItems == nil && tickerItems == nil && nameItems == nil { throw CoverageClientError.unavailable }
        return ticker + (feedItems ?? []) + (nameItems ?? [])
    }

    private func yahooFeed(symbol: String) async throws -> [CoverageItem] {
        guard var parts = URLComponents(string: "https://finance.yahoo.com/rss/headline") else {
            throw CoverageClientError.invalidURL
        }
        parts.queryItems = [URLQueryItem(name: "s", value: symbol)]
        guard let url = parts.url else { throw CoverageClientError.invalidURL }
        return try Self.yahooFeedItems(await request(url))
    }

    static func yahooFeedItems(_ data: Data) throws -> [CoverageItem] {
        let parser = XMLParser(data: data)
        let delegate = CoverageRSSParser()
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        guard parser.parse() else { throw CoverageClientError.invalidResponse }
        return delegate.items.compactMap { item in
            guard !item.title.isEmpty, let url = safeURL(item.link) else { return nil }
            let publisher = item.fields["source"] ?? item.fields["dc:creator"] ??
                (url.host == "finance.yahoo.com" ? "Yahoo Finance" : url.host ?? "Yahoo Finance")
            return CoverageItem(title: item.title,
                publisher: publisher,
                url: url, publishedAt: parseRSSDate(item.fields["pubDate"]), publishedLabel: nil)
        }
    }

    private func yahooSearch(_ query: String) async throws -> [CoverageItem] {
        guard var components = URLComponents(
            url: YahooAPIEndpoint.primary.appendingPathComponent("v1/finance/search"),
            resolvingAgainstBaseURL: false
        ) else { throw CoverageClientError.invalidURL }
        components.queryItems = [URLQueryItem(name: "q", value: query),
                                 URLQueryItem(name: "quotesCount", value: "0"),
                                 URLQueryItem(name: "newsCount", value: "100")]
        guard let url = components.url else { throw CoverageClientError.invalidURL }
        return try Self.yahooSearchItems(await request(url))
    }

    static func yahooSearchItems(_ data: Data) throws -> [CoverageItem] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let news = root["news"] as? [[String: Any]] else { throw CoverageClientError.invalidResponse }
        return news.compactMap { entry in
            guard let title = entry["title"] as? String, !title.isEmpty,
                  let rawURL = entry["link"] as? String, let url = safeURL(rawURL) else { return nil }
            let published = (entry["providerPublishTime"] as? NSNumber).map {
                Date(timeIntervalSince1970: $0.doubleValue)
            }
            return CoverageItem(title: title, publisher: entry["publisher"] as? String ?? "Yahoo Finance",
                                url: url, publishedAt: published, publishedLabel: nil)
        }
    }

    private func benzingaNews(symbol: String, companyName: String) async throws -> [CoverageItem] {
        let data = try await request(URL(string: "https://www.benzinga.com/feed")!)
        return try parseRSS(data, symbol: symbol, companyName: companyName, publisher: "Benzinga", dateField: "pubDate")
    }

    private func wallstreetOnlineNews(symbol: String, companyName: String) async throws -> [CoverageItem] {
        async let stockItems = stockPageNews(symbol: symbol, companyName: companyName)
        async let feedItems = wallstreetOnlineFeed(symbol: symbol, companyName: companyName)
        let stock = try? await stockItems
        let feed = try? await feedItems
        if stock == nil && feed == nil { throw CoverageClientError.unavailable }
        return (stock ?? []) + (feed ?? [])
    }

    private func stockPageNews(symbol: String, companyName: String) async throws -> [CoverageItem] {
        let slug = searchName(companyName).lowercased().replacingOccurrences(
            of: "[^a-z0-9]+", with: "-", options: .regularExpression
        ).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        guard slug.count >= 4, slug != symbol.lowercased(),
              let url = URL(string: "aktien/\(slug)-aktie/nachrichten",
                            relativeTo: ProviderEndpointStore.url(for: .wallstreetOnline))?.absoluteURL else {
            return []
        }
        let html = String(decoding: try await request(url), as: UTF8.self)
        guard let heading = firstCapture(#"(?is)<h1\b[^>]*>(.*?)</h1>"#, in: html),
              matchesCompany(plainText(heading), symbol: symbol, companyName: companyName) else { return [] }
        let rows = captures(#"(?is)<tr\b[^>]*>(?:(?!</tr>).)*newsListSubtitle(?:(?!</tr>).)*</tr>"#, in: html)
        return rows.prefix(30).compactMap { row in
            guard let href = firstCapture(#"(?is)<a\b[^>]*href=["']([^"']*/nachricht/[^"']*)["'][^>]*>(.*?)</a>"#, in: row, group: 1),
                  let titleHTML = firstCapture(#"(?is)<a\b[^>]*href=["'][^"']*/nachricht/[^"']*["'][^>]*>(.*?)</a>"#, in: row),
                  let url = Self.safeURL(href, base: ProviderEndpointStore.url(for: .wallstreetOnline)) else { return nil }
            let title = plainText(titleHTML)
            guard !title.isEmpty else { return nil }
            let subtitle = firstCapture(#"(?is)newsListSubtitle[^>]*>(.*?)</[^>]+>"#, in: row).map(plainText) ?? ""
            let parts = subtitle.components(separatedBy: "·").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            let date = parts.first.flatMap(parseGermanDate)
            return CoverageItem(title: title, publisher: parts.dropFirst().first ?? "wallstreetONLINE",
                                url: url, publishedAt: date, publishedLabel: parts.first)
        }
    }

    private func wallstreetOnlineFeed(symbol: String, companyName: String) async throws -> [CoverageItem] {
        let url = ProviderEndpointStore.url(for: .wallstreetOnline).appendingPathComponent("rss/nachrichten-alle.xml")
        return try parseRSS(await request(url), symbol: symbol, companyName: companyName,
                            publisher: "wallstreetONLINE", dateField: "dc:date")
    }

    private func request(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Mozilla/5.0 MiMiTrends", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200, data.count <= 4_000_000 else {
            throw CoverageClientError.unavailable
        }
        return data
    }

    private func parseRSS(
        _ data: Data, symbol: String, companyName: String, publisher: String, dateField: String
    ) throws -> [CoverageItem] {
        let parser = XMLParser(data: data)
        let delegate = CoverageRSSParser()
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        guard parser.parse() else { throw CoverageClientError.invalidResponse }
        return delegate.items.compactMap { item in
            guard !item.title.isEmpty,
                  matchesCompany("\(item.title) \(item.description)", symbol: symbol, companyName: companyName),
                  let url = Self.safeURL(item.link) else { return nil }
            let date = item.fields[dateField].flatMap(Self.parseRSSDate)
            return CoverageItem(title: item.title, publisher: publisher, url: url,
                                publishedAt: date, publishedLabel: nil)
        }
    }

    private func matchesCompany(_ text: String, symbol: String, companyName: String) -> Bool {
        let terms = [searchName(companyName), symbol.split(separator: ".").first.map(String.init) ?? symbol]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 4 }
        return terms.contains { term in
            text.range(of: "(?i)(?<![\\p{Alnum}])\(NSRegularExpression.escapedPattern(for: term))(?![\\p{Alnum}])",
                       options: .regularExpression) != nil
        }
    }

    private func searchName(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"(?i)\s+(inc\.?|corp\.?|corporation|ag|se|plc|ltd\.?)$"#,
                                  with: "", options: .regularExpression)
    }

    private static func safeURL(_ value: String, base: URL? = nil) -> URL? {
        let url = URL(string: value, relativeTo: base)?.absoluteURL
        return url?.scheme.map { ["https", "http"].contains($0.lowercased()) } == true ? url : nil
    }

    private func firstCapture(_ pattern: String, in value: String, group: Int = 1) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
              let range = Range(match.range(at: group), in: value) else { return nil }
        return String(value[range])
    }

    private func captures(_ pattern: String, in value: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: value, range: NSRange(value.startIndex..., in: value)).compactMap { match in
            Range(match.range, in: value).map { String(value[$0]) }
        }
    }

    private func plainText(_ html: String) -> String {
        html.replacingOccurrences(of: #"(?is)<[^>]+>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&auml;", with: "ä").replacingOccurrences(of: "&ouml;", with: "ö")
            .replacingOccurrences(of: "&uuml;", with: "ü").replacingOccurrences(of: "&Auml;", with: "Ä")
            .replacingOccurrences(of: "&Ouml;", with: "Ö").replacingOccurrences(of: "&Uuml;", with: "Ü")
            .replacingOccurrences(of: "&szlig;", with: "ß")
            .split(whereSeparator: \.isWhitespace).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func parseGermanDate(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Europe/Berlin")
        formatter.dateFormat = "dd.MM.yy"
        return formatter.date(from: value)
    }

    private static func parseRSSDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        if let date = ISO8601DateFormatter().date(from: value) { return date }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter.date(from: value)
    }
}

private struct SourceResult: Sendable {
    let items: [CoverageItem]
    let unavailable: String?
}

private struct CoverageRSSItem {
    var fields: [String: String] = [:]
    var title: String { fields["title"] ?? "" }
    var link: String { fields["link"] ?? "" }
    var description: String { fields["description"] ?? "" }
}

private final class CoverageRSSParser: NSObject, XMLParserDelegate, @unchecked Sendable {
    private(set) var items: [CoverageRSSItem] = []
    private var current: CoverageRSSItem?
    private var currentField: String?
    private var text = ""

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes: [String: String] = [:]) {
        if elementName == "item" { current = CoverageRSSItem() }
        else if current != nil { currentField = elementName; text = "" }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }
    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        text += String(data: CDATABlock, encoding: .utf8) ?? ""
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "item", let current { items.append(current); self.current = nil }
        else if currentField == elementName {
            current?.fields[elementName] = text.trimmingCharacters(in: .whitespacesAndNewlines)
            currentField = nil
        }
    }
}

private enum CoverageClientError: Error { case invalidURL, invalidResponse, unavailable }
