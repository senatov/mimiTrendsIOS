import Foundation

enum RadarScanThresholdDefaults {
    static let shortDropPercent = 1.0
    static let sustainedDropPercent = 1.5
    static let legacyShortDropPercent = 0.35
    static let legacySustainedDropPercent = 0.55
}

struct RadarScanPreferences: Codable, Equatable, Sendable {
    var crashPercent = RadarScanThresholdDefaults.shortDropPercent
    var crashWindowMinutes = 5
    var sustainedCrashPercent = RadarScanThresholdDefaults.sustainedDropPercent
    var sustainedCrashWindowMinutes = 15
    var risePercent = 0.8
    var riseWindowMinutes = 5
    var minimumPrice = 5.0
    var minimumTurnover = 250_000.0
    var sustainedMovePercent = 0.8
    var sustainedMoveWindowMinutes = 180
    var sustainedMoveMinimumTurnover = 50_000_000.0

    var validated: Self {
        var result = self
        result.crashPercent = Self.bounded(
            crashPercent, 0.05...20, fallback: RadarScanThresholdDefaults.shortDropPercent
        )
        result.crashWindowMinutes = crashWindowMinutes.clamped(to: 4...15)
        result.sustainedCrashPercent = Self.bounded(
            sustainedCrashPercent, 0.05...20, fallback: RadarScanThresholdDefaults.sustainedDropPercent
        )
        result.sustainedCrashWindowMinutes = sustainedCrashWindowMinutes.clamped(to: 5...30)
        result.risePercent = Self.bounded(risePercent, 0.05...20, fallback: 0.8)
        result.riseWindowMinutes = riseWindowMinutes.clamped(to: 1...15)
        result.minimumPrice = Self.bounded(minimumPrice, 0...10_000, fallback: 5)
        result.minimumTurnover = Self.bounded(minimumTurnover, 0...10_000_000, fallback: 250_000)
        result.sustainedMovePercent = Self.bounded(sustainedMovePercent, 0.1...20, fallback: 0.8)
        result.sustainedMoveWindowMinutes = sustainedMoveWindowMinutes.clamped(to: 30...360)
        result.sustainedMoveMinimumTurnover = Self.bounded(
            sustainedMoveMinimumTurnover, 0...10_000_000_000, fallback: 50_000_000
        )
        return result
    }

    var rapidRise: RapidRiseSettings {
        RapidRiseSettings(
            risePercent: risePercent, riseWindowMinutes: Int64(riseWindowMinutes),
            minimumPrice: minimumPrice, minimumTurnover: minimumTurnover
        )
    }

    var rapidCrash: RapidCrashSettings {
        RapidCrashSettings(
            crashPercent: crashPercent, crashWindowMinutes: Int64(crashWindowMinutes),
            sustainedCrashPercent: sustainedCrashPercent,
            sustainedCrashWindowMinutes: Int64(sustainedCrashWindowMinutes),
            minimumPrice: minimumPrice, minimumTurnover: minimumTurnover
        )
    }

    var sustainedMove: SustainedMoveSettings {
        SustainedMoveSettings(
            movePercent: sustainedMovePercent,
            windowMinutes: Int64(sustainedMoveWindowMinutes),
            minimumTurnover: sustainedMoveMinimumTurnover,
            minimumPrice: minimumPrice
        )
    }

    private static func bounded(_ value: Double, _ range: ClosedRange<Double>, fallback: Double) -> Double {
        value.isFinite ? min(max(value, range.lowerBound), range.upperBound) : fallback
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
