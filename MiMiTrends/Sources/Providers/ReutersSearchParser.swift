import Foundation

/// Reads the dated story cards rendered by Reuters site search.
enum ReutersSearchParser {
    static func parse(_ data: Data) -> [CoverageItem] {
        let html = String(decoding: data, as: UTF8.self)
        let cards = captures(#"(?is)<li\b(?=[^>]*data-testid=["']StoryCard["'])[^>]*>(.*?)</li>"#, in: html)
        let base = URL(string: "https://www.reuters.com")!
        return cards.compactMap { card in
            guard let href = firstCapture(
                #"(?is)<a\b(?=[^>]*data-testid=["']TitleLink["'])[^>]*href=["']([^"']+)["']"#, in: card
            ), let heading = firstCapture(
                #"(?is)<span\b(?=[^>]*data-testid=["']TitleHeading["'])[^>]*>(.*?)</span>"#, in: card
            ), let dateText = firstCapture(
                #"(?is)<time\b(?=[^>]*data-testid=["']DateLineText["'])[^>]*datetime=["']([^"']+)["']"#, in: card
            ), let date = publicationDate(dateText),
                  let url = URL(string: href, relativeTo: base)?.absoluteURL,
                  url.scheme == "https", url.host == "www.reuters.com" else { return nil }
            let title = plainText(heading)
            guard !title.isEmpty else { return nil }
            return CoverageItem(title: title, publisher: "Reuters", url: url,
                                publishedAt: date, publishedLabel: nil)
        }
    }

    private static func publicationDate(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }

    private static func plainText(_ html: String) -> String {
        html.replacingOccurrences(of: #"(?is)<[^>]+>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func captures(_ pattern: String, in value: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: value, range: NSRange(value.startIndex..., in: value)).compactMap { match in
            Range(match.range, in: value).map { String(value[$0]) }
        }
    }

    private static func firstCapture(_ pattern: String, in value: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
              let range = Range(match.range(at: 1), in: value) else { return nil }
        return String(value[range])
    }
}
