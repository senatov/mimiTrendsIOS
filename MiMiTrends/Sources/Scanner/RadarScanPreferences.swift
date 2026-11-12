import Foundation

enum RadarScanThresholdDefaults {
    static let shortDropPercent = 0.8
    static let shortDropWindowMinutes = 5
    static let sustainedDropPercent = 2.0
    static let sustainedDropWindowMinutes = 15
    static let legacyShortDropPercent = 0.35
    static let legacySustainedDropPercent = 0.55
    static let sharpReboundPercent = 0.8
    static let sharpReboundWindowMinutes = 5
    static let smoothRisePercent = 1.2
    static let smoothRiseWindowMinutes = 120
    static let smoothRiseMaximumPullbackPercent = 0.75
}

struct RadarScanPreferences: Codable, Equatable, Sendable {
    var crashPercent = RadarScanThresholdDefaults.shortDropPercent
    var crashWindowMinutes = RadarScanThresholdDefaults.shortDropWindowMinutes
    var sustainedCrashPercent = RadarScanThresholdDefaults.sustainedDropPercent
    var sustainedCrashWindowMinutes = RadarScanThresholdDefaults.sustainedDropWindowMinutes
    var risePercent = RadarScanThresholdDefaults.sharpReboundPercent
    var riseWindowMinutes = RadarScanThresholdDefaults.sharpReboundWindowMinutes
    var minimumPrice = 5.0
    var minimumTurnover = 250_000.0
    var sustainedMovePercent = RadarScanThresholdDefaults.smoothRisePercent
    var sustainedMoveWindowMinutes = RadarScanThresholdDefaults.smoothRiseWindowMinutes
    var sustainedMoveMinimumTurnover = 50_000_000.0
    var smoothRiseMaximumPullbackPercent = RadarScanThresholdDefaults.smoothRiseMaximumPullbackPercent

    private enum CodingKeys: String, CodingKey {
        case crashPercent, crashWindowMinutes, sustainedCrashPercent, sustainedCrashWindowMinutes
        case risePercent, riseWindowMinutes, minimumPrice, minimumTurnover
        case sustainedMovePercent, sustainedMoveWindowMinutes, sustainedMoveMinimumTurnover
        case smoothRiseMaximumPullbackPercent
    }

    init() {}

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Self()
        crashPercent = try values.decodeIfPresent(Double.self, forKey: .crashPercent) ?? defaults.crashPercent
        crashWindowMinutes = try values.decodeIfPresent(Int.self, forKey: .crashWindowMinutes) ?? defaults.crashWindowMinutes
        sustainedCrashPercent = try values.decodeIfPresent(Double.self, forKey: .sustainedCrashPercent) ?? defaults.sustainedCrashPercent
        sustainedCrashWindowMinutes = try values.decodeIfPresent(Int.self, forKey: .sustainedCrashWindowMinutes) ?? defaults.sustainedCrashWindowMinutes
        risePercent = try values.decodeIfPresent(Double.self, forKey: .risePercent) ?? defaults.risePercent
        riseWindowMinutes = try values.decodeIfPresent(Int.self, forKey: .riseWindowMinutes) ?? defaults.riseWindowMinutes
        minimumPrice = try values.decodeIfPresent(Double.self, forKey: .minimumPrice) ?? defaults.minimumPrice
        minimumTurnover = try values.decodeIfPresent(Double.self, forKey: .minimumTurnover) ?? defaults.minimumTurnover
        sustainedMovePercent = try values.decodeIfPresent(Double.self, forKey: .sustainedMovePercent) ?? defaults.sustainedMovePercent
        sustainedMoveWindowMinutes = try values.decodeIfPresent(Int.self, forKey: .sustainedMoveWindowMinutes) ?? defaults.sustainedMoveWindowMinutes
        sustainedMoveMinimumTurnover = try values.decodeIfPresent(Double.self, forKey: .sustainedMoveMinimumTurnover) ?? defaults.sustainedMoveMinimumTurnover
        smoothRiseMaximumPullbackPercent = try values.decodeIfPresent(
            Double.self, forKey: .smoothRiseMaximumPullbackPercent
        ) ?? defaults.smoothRiseMaximumPullbackPercent
    }

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
        result.risePercent = Self.bounded(
            risePercent, 0.05...20, fallback: RadarScanThresholdDefaults.sharpReboundPercent
        )
        result.riseWindowMinutes = riseWindowMinutes.clamped(to: 3...15)
        result.minimumPrice = Self.bounded(minimumPrice, 0...10_000, fallback: 5)
        result.minimumTurnover = Self.bounded(minimumTurnover, 0...10_000_000, fallback: 250_000)
        result.sustainedMovePercent = Self.bounded(
            sustainedMovePercent, 0.1...20, fallback: RadarScanThresholdDefaults.smoothRisePercent
        )
        result.sustainedMoveWindowMinutes = sustainedMoveWindowMinutes.clamped(to: 30...360)
        result.sustainedMoveMinimumTurnover = Self.bounded(
            sustainedMoveMinimumTurnover, 0...10_000_000_000, fallback: 50_000_000
        )
        result.smoothRiseMaximumPullbackPercent = Self.bounded(
            smoothRiseMaximumPullbackPercent, 0.1...5,
            fallback: RadarScanThresholdDefaults.smoothRiseMaximumPullbackPercent
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

    var smoothRise: SmoothRiseSettings {
        SmoothRiseSettings(
            movePercent: sustainedMovePercent,
            windowMinutes: Int64(sustainedMoveWindowMinutes),
            maximumPullbackPercent: smoothRiseMaximumPullbackPercent,
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
