import Foundation

enum RadarTradingPhase: Equatable {
    case closed, preMarket, regular, afterHours

    var isTrading: Bool { self != .closed }
}

enum RadarTradingMarket {
    case germany, unitedStates

    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: self == .germany ? "Europe/Berlin" : "America/New_York")!
        return calendar
    }

    func phase(at date: Date) -> RadarTradingPhase {
        session(at: date)?.phase ?? .closed
    }

    func sessionStart(at date: Date) -> Date? {
        guard let session = session(at: date) else { return nil }
        return calendar.date(bySettingHour: session.start / 60, minute: session.start % 60,
                             second: 0, of: date)
    }

    private func session(at date: Date) -> (phase: RadarTradingPhase, start: Int)? {
        let calendar = self.calendar
        let parts = calendar.dateComponents([.year, .month, .day, .weekday, .hour, .minute], from: date)
        guard let weekday = parts.weekday, (2...6).contains(weekday),
              let year = parts.year, let month = parts.month, let day = parts.day,
              let hour = parts.hour, let minute = parts.minute else { return nil }
        let time = hour * 60 + minute
        let easter = Self.easter(year, calendar: calendar)
        func easterOffset(_ offset: Int) -> Bool {
            guard let easter, let target = calendar.date(byAdding: .day, value: offset, to: easter) else {
                return false
            }
            return calendar.isDate(date, inSameDayAs: target)
        }
        guard !easterOffset(-2) else { return nil }

        switch self {
        case .germany:
            let holidays = [(1, 1), (5, 1), (12, 24), (12, 25), (12, 26), (12, 31)]
            guard !holidays.contains(where: { $0 == (month, day) }), !easterOffset(1) else { return nil }
            let shortExtended = easterOffset(39) || easterOffset(50) || easterOffset(60)
                || (month == 10 && day == 3)
            // Deutsche Börse final trading session announcement for 2026.
            let endOfYear = year == 2026 && month == 12 && day == 30
            return Self.session(time, start: 480, open: 540, close: endOfYear ? 840 : 1050,
                              end: endOfYear ? 840 : shortExtended ? 1200 : 1320)
        case .unitedStates:
            func observed(_ holidayMonth: Int, _ holidayDay: Int, saturday: Bool = true) -> Bool {
                guard let holiday = calendar.date(from: DateComponents(
                    year: year, month: holidayMonth, day: holidayDay
                )) else { return false }
                let weekday = calendar.component(.weekday, from: holiday)
                let shift = weekday == 1 ? 1 : weekday == 7 && saturday ? -1 : 0
                guard let observed = calendar.date(byAdding: .day, value: shift, to: holiday) else {
                    return false
                }
                return calendar.isDate(date, inSameDayAs: observed)
            }
            let thanksgiving = month == 11 && weekday == 5 && (22...28).contains(day)
            let mondayHoliday = weekday == 2 && (
                ((month == 1 || month == 2) && (15...21).contains(day))
                || (month == 5 && day >= 25) || (month == 9 && day <= 7)
            )
            guard !mondayHoliday, !thanksgiving, !observed(1, 1, saturday: false),
                  !observed(6, 19), !observed(7, 4), !observed(12, 25) else { return nil }
            let earlyClose = (month == 11 && weekday == 6 && (23...29).contains(day))
                || (month == 12 && day == 24) || (month == 7 && day == 3)
            return Self.session(time, start: 240, open: 570, close: earlyClose ? 780 : 960,
                              end: earlyClose ? 1020 : 1200)
        }
    }

    private static func session(_ time: Int, start: Int, open: Int, close: Int, end: Int)
        -> (phase: RadarTradingPhase, start: Int)? {
        guard time >= start, time < end else { return nil }
        if time < open { return (.preMarket, start) }
        return time < close ? (.regular, open) : (.afterHours, close)
    }

    private static func easter(_ year: Int, calendar: Calendar) -> Date? {
        let a = year % 19, b = year / 100, c = year % 100
        let d = b / 4, e = b % 4, f = (b + 8) / 25
        let g = (b - f + 1) / 3
        let h = (19 * a + b - d - g + 15) % 30
        let i = c / 4, k = c % 4
        let l = (32 + 2 * e + 2 * i - h - k) % 7
        let m = (a + 11 * h + 22 * l) / 451
        let value = h + l - 7 * m + 114
        return calendar.date(from: DateComponents(
            year: year, month: value / 31, day: value % 31 + 1
        ))
    }
}

enum GermanMarketSession {
    static func isOpen(at date: Date) -> Bool {
        RadarTradingMarket.germany.phase(at: date) == .regular
    }
}

struct RadarTradingSessions: Equatable {
    static let refreshInterval: TimeInterval = 25 * 60

    let german: RadarTradingPhase
    let us: RadarTradingPhase
    let germanOpeningSoon: Bool
    let usOpeningSoon: Bool

    init(at date: Date) {
        german = RadarTradingMarket.germany.phase(at: date)
        us = RadarTradingMarket.unitedStates.phase(at: date)
        let soon = date.addingTimeInterval(15 * 60)
        germanOpeningSoon = german == .preMarket && RadarTradingMarket.germany.phase(at: soon) == .regular
        usOpeningSoon = us == .preMarket && RadarTradingMarket.unitedStates.phase(at: soon) == .regular
    }
}
