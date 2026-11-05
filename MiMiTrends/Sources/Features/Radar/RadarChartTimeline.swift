import Foundation

/// One display slot per observed candle; closed sessions consume no empty space.
struct RadarChartTimeline {
    let bars: [MinuteBar]

    var domain: ClosedRange<Double> {
        -30...(Double(max(1, bars.count) - 1) * 60 + 30)
    }

    var ticks: [Double] {
        guard !bars.isEmpty else { return [] }
        return stride(from: 0, to: bars.count, by: max(1, bars.count / 6))
            .map { Double($0) * 60 }
    }

    func position(_ epoch: Int64) -> Double {
        guard let first = bars.first, epoch > first.minuteEpochSeconds else {
            return 0
        }
        for index in 1..<bars.count where bars[index].minuteEpochSeconds >= epoch {
            let left = bars[index - 1].minuteEpochSeconds
            let span = max(1, bars[index].minuteEpochSeconds - left)
            let fraction = Double(epoch - left) / Double(span)
            return (Double(index - 1) + fraction) * 60
        }
        return Double(max(0, bars.count - 1)) * 60
    }

    func bar(at displayPosition: Double) -> MinuteBar? {
        guard !bars.isEmpty else { return nil }
        let index = min(max(Int((displayPosition / 60).rounded()), 0), bars.count - 1)
        return bars[index]
    }
}
