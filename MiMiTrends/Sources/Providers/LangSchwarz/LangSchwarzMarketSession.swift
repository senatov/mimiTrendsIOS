import Foundation

enum LangSchwarzMarketSession {
    static func isUnderlyingMarketOpen(for endpoint: ProviderEndpoint, at date: Date) -> Bool {
        switch endpoint {
        case .langSchwarzAmerica:
            return isOpen(date, timeZoneID: "America/New_York", start: 9 * 60 + 30, end: 16 * 60)
        case .langSchwarzGermany, .langSchwarzStoxx, .langSchwarzEurope:
            return GermanMarketSession.isOpen(at: date)
        default:
            return false
        }
    }

    static func isQuoteVenueOpen(at date: Date) -> Bool {
        guard let timeZone = TimeZone(identifier: "Europe/Berlin") else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.weekday, .hour, .minute], from: date)
        guard let weekday = parts.weekday, let hour = parts.hour, let minute = parts.minute else { return false }
        let minuteOfDay = hour * 60 + minute
        switch weekday {
        case 2...6: return (7 * 60 + 30..<23 * 60).contains(minuteOfDay)
        case 7: return (10 * 60..<13 * 60).contains(minuteOfDay)
        case 1: return (17 * 60..<19 * 60).contains(minuteOfDay)
        default: return false
        }
    }

    static func underlyingOpenEndpoints(at date: Date) -> [ProviderEndpoint] {
        [ProviderEndpoint.langSchwarzGermany, .langSchwarzStoxx, .langSchwarzEurope, .langSchwarzAmerica]
            .filter { isUnderlyingMarketOpen(for: $0, at: date) }
    }

    private static func isOpen(_ date: Date, timeZoneID: String, start: Int, end: Int) -> Bool {
        guard let timeZone = TimeZone(identifier: timeZoneID) else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.weekday, .hour, .minute], from: date)
        guard let weekday = parts.weekday, (2...6).contains(weekday),
              let hour = parts.hour, let minute = parts.minute else { return false }
        let minuteOfDay = hour * 60 + minute
        return (start..<end).contains(minuteOfDay)
    }
}
