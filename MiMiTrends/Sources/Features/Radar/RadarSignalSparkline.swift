import SwiftUI

/// A fixed view of the 45 minutes leading up to a Radar event.
struct RadarSparklineSeries: Sendable {
    struct Point: Sendable {
        let minute: Int64
        let close: Double
    }

    let points: [Point]
    let highlightedFrom: Int

    init?(bars: [MinuteBar], eventMillis: Int64) {
        let eventSecond = eventMillis / 1_000
        let selected = bars.filter {
            $0.isValid && $0.minuteEpochSeconds >= eventSecond - 45 * 60 &&
                $0.minuteEpochSeconds <= eventSecond
        }.sorted { $0.minuteEpochSeconds < $1.minuteEpochSeconds }
        guard selected.count >= 3 else { return nil }
        points = selected.map { Point(minute: $0.minuteEpochSeconds, close: $0.close) }
        highlightedFrom = min(points.count - 2, max(1, points.firstIndex {
            $0.minute >= eventSecond - 10 * 60
        } ?? points.count - 2))
    }

    var changePercent: Double {
        guard let first = points.first?.close, let last = points.last?.close else { return 0 }
        return (last / first - 1) * 100
    }
}

actor RadarSparklineHistory {
    static let shared = RadarSparklineHistory()

    private struct Key: Hashable {
        let symbol: String
        let eventMillis: Int64
    }

    private var cached: [Key: (series: RadarSparklineSeries?, loadedAt: Date)] = [:]
    private var pending: [Key: Task<RadarSparklineSeries?, Never>] = [:]
    private var activeLoads = 0
    private var waitingLoads: [CheckedContinuation<Void, Never>] = []

    func series(symbol: String, eventMillis: Int64) async -> RadarSparklineSeries? {
        let key = Key(symbol: symbol, eventMillis: eventMillis)
        if let cachedValue = cached[key],
           cachedValue.series != nil || Date().timeIntervalSince(cachedValue.loadedAt) < 300 {
            return cachedValue.series
        }
        if let task = pending[key] { return await task.value }
        let task = Task(priority: .utility) {
            await self.acquireLoadSlot()
            let result = await Self.load(symbol: symbol, eventMillis: eventMillis)
            self.releaseLoadSlot()
            return result
        }
        pending[key] = task
        let result = await task.value
        cached[key] = (result, Date())
        pending[key] = nil
        return result
    }

    private func acquireLoadSlot() async {
        if activeLoads < 2 {
            activeLoads += 1
        } else {
            await withCheckedContinuation { waitingLoads.append($0) }
        }
    }

    private func releaseLoadSlot() {
        if waitingLoads.isEmpty {
            activeLoads -= 1
        } else {
            waitingLoads.removeFirst().resume()
        }
    }

    private static func load(symbol: String, eventMillis: Int64) async -> RadarSparklineSeries? {
        let eventSecond = eventMillis / 1_000
        if let store = try? MarketBarStore(url: MarketBarStore.defaultURL()),
           let bars = try? await store.loadRecentMinuteBars(
               symbol: symbol, fromEpochSeconds: eventSecond - 45 * 60,
               throughEpochSeconds: eventSecond, limit: 46),
           bars.first.map({ $0.minuteEpochSeconds <= eventSecond - 25 * 60 }) == true,
           let series = RadarSparklineSeries(bars: bars, eventMillis: eventMillis) {
            return series
        }
        guard MarketProviderAccess.isEnabled(.yahoo) else { return nil }
        do {
            let bars = try await YahooRadarSource().historicalMinuteBars(
                symbol: symbol, from: eventSecond - 45 * 60, through: eventSecond + 60)
            return RadarSparklineSeries(bars: bars, eventMillis: eventMillis)
        } catch {
            if !(error is CancellationError) {
                AppDiagnostics.shared.record(.warning, "Radar", "sparkline-history-unavailable",
                    "symbol=\(symbol) error=\(String(describing: type(of: error)))")
            }
            return nil
        }
    }
}

struct RadarSignalSparkline: View {
    @Environment(RadarTableColorStore.self) private var tableColors
    @Environment(\.colorScheme) private var colorScheme
    let symbol: String
    let eventMillis: Int64
    let falling: Bool
    @State private var series: RadarSparklineSeries?

    var body: some View {
        Group {
            if let series {
                GeometryReader { geometry in
                    let prices = series.points.map(\.close)
                    let low = prices.min() ?? 0
                    let high = prices.max() ?? low
                    let spread = max(high - low, max(high * 0.001, 0.001))
                    let first = series.points[0].minute
                    let duration = max(1, (series.points.last?.minute ?? first) - first)
                    let coordinates = series.points.map { point in
                        CGPoint(x: geometry.size.width * CGFloat(point.minute - first) / CGFloat(duration),
                                y: 2 + (geometry.size.height - 4) * CGFloat((high - point.close) / spread))
                    }
                    Path { path in
                        let y = 2 + (geometry.size.height - 4) * CGFloat((high - prices[0]) / spread)
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: geometry.size.width, y: y))
                    }
                    .stroke(.secondary.opacity(0.35), lineWidth: 0.7)
                    line(coordinates, minutes: series.points.map(\.minute),
                         from: 0, through: series.highlightedFrom)
                        .stroke(.secondary.opacity(0.75), style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
                    line(coordinates, minutes: series.points.map(\.minute),
                         from: series.highlightedFrom, through: coordinates.count - 1)
                        .stroke(tableColors.color(falling ? .fall : .rise, dark: colorScheme == .dark),
                                style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                }
                .accessibilityLabel("Yahoo minute price history before event, \(series.changePercent.formatted(.number.sign(strategy: .always()).precision(.fractionLength(1)))) percent")
                .help("Yahoo minute prices up to 45 minutes before this event")
            } else {
                Image(systemName: "chart.xyaxis.line")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel("Minute price history unavailable")
                    .help("Minute price history unavailable")
            }
        }
        .frame(width: 66, height: 20)
        .task(id: "\(symbol)|\(eventMillis)") {
            series = await RadarSparklineHistory.shared.series(symbol: symbol, eventMillis: eventMillis)
        }
    }

    private func line(_ points: [CGPoint], minutes: [Int64], from start: Int, through end: Int) -> Path {
        Path { path in
            guard start < end, points.indices.contains(start) else { return }
            path.move(to: points[start])
            for index in (start + 1)...end {
                if minutes[index] - minutes[index - 1] > 180 {
                    path.move(to: points[index])
                } else {
                    path.addLine(to: points[index])
                }
            }
        }
    }
}
