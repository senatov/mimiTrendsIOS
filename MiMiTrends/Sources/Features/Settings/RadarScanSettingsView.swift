import SwiftUI

struct RadarScanSettingsView: View {
    @Environment(RadarSession.self) private var radarSession
    @State private var draft = RadarScanPreferences()
    @State private var saved = RadarScanPreferences()
    @State private var message: String?
    @State private var didLoad = false

    var body: some View {
        SettingsPage(title: "Rapid moves", subtitle: "Thresholds for confirmed price changes") { width in
            if width >= 900 {
                HStack(alignment: .top, spacing: 18) {
                    VStack(spacing: 18) {
                        crashGroup
                        riseGroup
                    }
                    .frame(maxWidth: .infinity)
                    VStack(spacing: 18) {
                        sustainedGroup
                        qualityGroup
                    }
                    .frame(maxWidth: .infinity)
                }
            } else {
                crashGroup
                riseGroup
                sustainedGroup
                qualityGroup
            }
        }
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            saved = RadarScanPreferencesStore.load()
            draft = saved
        }
    }

    private var crashGroup: some View {
        section("Very sharp drops") {
            Text(crashDescription)
                .font(.body.weight(.light))
                .foregroundStyle(TrendsColors.supportingInk)
            doubleRow("Short-window drop", value: $draft.crashPercent, range: 0.05...20, step: 0.05, unit: "%")
            intRow("Short window", value: $draft.crashWindowMinutes, range: 4...15, unit: "min")
            doubleRow("Long-window drop", value: $draft.sustainedCrashPercent, range: 0.05...20, step: 0.05, unit: "%")
            intRow("Long window", value: $draft.sustainedCrashWindowMinutes, range: 5...30, unit: "min")
        }
    }

    private var crashDescription: String {
        let short = draft.crashPercent.formatted(.number.precision(.fractionLength(0...2)))
        let sustained = draft.sustainedCrashPercent.formatted(.number.precision(.fractionLength(0...2)))
        return "Short-term price-move alert: at least \(short)% in \(draft.crashWindowMinutes) minutes or \(sustained)% in \(draft.sustainedCrashWindowMinutes) minutes. Both rules require reported volume; the longer-window rule also requires a new low and acceleration."
    }

    private var riseGroup: some View {
        section("Sharp rebounds") {
            Text("A rebound must still be rising in the latest available bar after a recent low. This confirms a move already observed; it cannot guarantee what happens next.")
                .font(.body.weight(.light))
                .foregroundStyle(TrendsColors.supportingInk)
            doubleRow("Minimum rise", value: $draft.risePercent, range: 0.05...20, step: 0.05, unit: "%")
            intRow("Rise window", value: $draft.riseWindowMinutes, range: 1...15, unit: "min")
        }
    }

    private var sustainedGroup: some View {
        section("Smooth upward trend") {
            Text("Looks for a steady rise with limited pullbacks across 5-minute samples. No market signal can guarantee a future gain.")
                .font(.body.weight(.light))
                .foregroundStyle(TrendsColors.supportingInk)
            doubleRow("Minimum rise", value: $draft.sustainedMovePercent, range: 0.1...20, step: 0.1, unit: "%")
            intRow("Trend window", value: $draft.sustainedMoveWindowMinutes, range: 30...360, unit: "min")
            doubleRow("Maximum pullback", value: $draft.smoothRiseMaximumPullbackPercent, range: 0.1...5, step: 0.05, unit: "%")
            amountRow("Window turnover", value: $draft.sustainedMoveMinimumTurnover)
        }
    }

    private var qualityGroup: some View {
        section("Shared quality checks") {
            doubleRow("Minimum price", value: $draft.minimumPrice, range: 0...10_000, step: 0.5, unit: "")
            amountRow("30-minute turnover", value: $draft.minimumTurnover)
            Text("Turnover uses the instrument's source currency. Changes stop an active feed; start it again to scan with the saved thresholds.")
                .font(.body.weight(.light))
                .foregroundStyle(TrendsColors.supportingInk)
            HStack {
                TrendsActionButton(title: "Save thresholds", systemImage: "checkmark") { save() }
                    .disabled(draft == saved)
                TrendsActionButton(title: "Restore defaults", systemImage: "arrow.uturn.backward") {
                    draft = RadarScanPreferences()
                }
            }
            if let message {
                Text(message).font(.body.weight(.light)).foregroundStyle(TrendsColors.supportingInk)
            }
        }
    }

    private func section<Content: View>(
        _ title: String, @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        SettingsGroup(title: title) { content() }
    }

    private func save() {
        do {
            try RadarScanPreferencesStore.save(draft)
            saved = draft.validated
            draft = saved
            radarSession.stop()
            message = "Thresholds saved on this device."
        } catch {
            message = "Could not save scanner thresholds."
        }
    }

    private func doubleRow(
        _ title: String, value: Binding<Double>, range: ClosedRange<Double>,
        step: Double, unit: String
    ) -> some View {
        Stepper(value: value, in: range, step: step) {
            HStack {
                Text(title)
                Spacer()
                Text("\(value.wrappedValue.formatted(.number.precision(.fractionLength(step < 1 ? 2 : 0)))) \(unit)")
                    .monospacedDigit()
                    .foregroundStyle(TrendsColors.supportingInk)
            }
        }
        .accessibilityLabel(title)
    }

    private func intRow(
        _ title: String, value: Binding<Int>, range: ClosedRange<Int>, unit: String
    ) -> some View {
        Stepper(value: value, in: range) {
            HStack {
                Text(title)
                Spacer()
                Text("\(value.wrappedValue) \(unit)")
                    .monospacedDigit()
                    .foregroundStyle(TrendsColors.supportingInk)
            }
        }
        .accessibilityLabel(title)
    }

    private func amountRow(_ title: String, value: Binding<Double>) -> some View {
        HStack {
            Text(title)
            Spacer(minLength: 12)
            TextField(title, value: value, format: .number.precision(.fractionLength(0)))
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .frame(width: 160)
                .accessibilityLabel(title)
        }
    }
}
