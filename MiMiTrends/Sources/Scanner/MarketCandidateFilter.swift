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
        let isUS = FinnhubBidAskClient.supports(symbol: symbol) && usExchanges.contains(exchange)
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
        FinnhubBidAskClient.supports(symbol: symbol) ||
            symbol.uppercased().range(of: "^[A-Z0-9]{1,10}\\.DE$", options: .regularExpression) != nil
    }

    static func isGermanSymbol(_ symbol: String) -> Bool {
        symbol.uppercased().hasSuffix(".DE")
    }
}

enum GermanMarketSession {
    static func isOpen(at date: Date) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        guard let timeZone = TimeZone(identifier: "Europe/Berlin") else { return false }
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day, .weekday, .hour, .minute], from: date)
        guard let weekday = parts.weekday, (2...6).contains(weekday),
              let hour = parts.hour, let minute = parts.minute else { return false }
        guard let year = parts.year, let month = parts.month, let day = parts.day,
              !isHoliday(year: year, month: month, day: day, calendar: calendar) else { return false }
        let minuteOfDay = hour * 60 + minute
        return (9 * 60..<17 * 60 + 30).contains(minuteOfDay)
    }

    private static func isHoliday(year: Int, month: Int, day: Int, calendar: Calendar) -> Bool {
        if [(1, 1), (5, 1), (12, 24), (12, 25), (12, 26), (12, 31)].contains(where: {
            $0.0 == month && $0.1 == day
        }) { return true }
        // Gregorian Easter: Xetra closes on Good Friday and Easter Monday.
        let a = year % 19, b = year / 100, c = year % 100
        let d = b / 4, e = b % 4, f = (b + 8) / 25
        let g = (b - f + 1) / 3
        let h = (19 * a + b - d - g + 15) % 30
        let i = c / 4, k = c % 4
        let l = (32 + 2 * e + 2 * i - h - k) % 7
        let m = (a + 11 * h + 22 * l) / 451
        let value = h + l - 7 * m + 114
        guard let easter = calendar.date(from: DateComponents(
            year: year, month: value / 31, day: value % 31 + 1
        )) else { return true }
        return [-2, 1].contains { offset in
            guard let holiday = calendar.date(byAdding: .day, value: offset, to: easter) else { return false }
            let parts = calendar.dateComponents([.month, .day], from: holiday)
            return parts.month == month && parts.day == day
        }
    }

}
