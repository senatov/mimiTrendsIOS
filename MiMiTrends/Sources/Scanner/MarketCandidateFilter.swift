import Foundation

enum MarketCandidateFilter {
    private static let usExchanges: Set<String> = [
        "NASDAQ", "NMS", "NGM", "NCM", "NYSE", "NYQ", "AMEX", "ASE", "NYSE AMERICAN"
    ]
    private static let germanExchanges: Set<String> = ["XETRA", "XETR", "FRANKFURT", "FRA", "GER"]
    private static let excludedName = try! NSRegularExpression(
        pattern: #"\b(ETF|ETN|FUND|WARRANT|RIGHTS?|UNITS?|PREFERRED|PREFERENCE|LEVERAGED|[23]X)\b"#,
        options: .caseInsensitive
    )

    static func accepts(
        symbol: String, name: String, price: Double, exchange: String,
        currency: String? = nil, volume: Double? = nil, marketCap: Double? = nil
    ) -> Bool {
        guard price.isFinite, price >= 5,
              !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              excludedName.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)) == nil else {
            return false
        }
        let symbol = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let exchange = exchange.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let isUS = supportsUSSymbol(symbol) && usExchanges.contains(exchange)
        let isGerman = symbol.range(of: "^[A-Z0-9]{1,10}\\.DE$", options: .regularExpression) != nil
            && germanExchanges.contains(exchange)
        guard isUS || isGerman else { return false }
        if let currency, currency.uppercased() != (isGerman ? "EUR" : "USD") { return false }
        if let volume {
            guard volume.isFinite, volume > 0, price * volume >= 2_000_000 else { return false }
        }
        if let marketCap {
            guard marketCap.isFinite, marketCap >= 300_000_000 else { return false }
        }
        if isUS, ["-W", "-U", "-R", "-P"].contains(where: symbol.hasSuffix) { return false }
        return true
    }

    static func supportsYahooBars(symbol: String) -> Bool {
        supportsUSSymbol(symbol) ||
            symbol.uppercased().range(of: "^[A-Z0-9]{1,10}\\.DE$", options: .regularExpression) != nil
    }

    static func supportsUSSymbol(_ symbol: String) -> Bool {
        symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            .range(of: "^[A-Z][A-Z0-9-]{0,9}$", options: .regularExpression) != nil
    }

    static func isGermanSymbol(_ symbol: String) -> Bool {
        symbol.uppercased().hasSuffix(".DE")
    }
}
