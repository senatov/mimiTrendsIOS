import SwiftUI

struct RadarTelemetrySource: Identifiable {
    let name: String
    let status: String
    let statusColor: Color
    let dotColor: Color
    let received: Int?
    let valid: Int?
    let requests: Int?
    let errors: Int?

    var id: String { name }
}

struct RadarSourceTable: View {
    @Environment(RadarTableColorStore.self) private var tableColors
    @Environment(RadarTableTypographyStore.self) private var tableTypography
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let sources: [RadarTelemetrySource]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(sources) { source in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(source.dotColor)
                            .frame(width: 6, height: 6)
                            .accessibilityHidden(true)
                        Text(source.name)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(source.status)
                            .font(statusFont)
                            .foregroundStyle(source.statusColor)
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                            .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.8)
                    }
                    Group {
                        if dynamicTypeSize.isAccessibilitySize {
                            VStack(spacing: 2) {
                                HStack { metric("Recv", source.received); metric("Valid", source.valid) }
                                HStack { metric("Req", source.requests); metric("Err", source.errors) }
                            }
                        } else {
                            HStack(spacing: 0) {
                                metric("Recv", source.received)
                                metric("Valid", source.valid)
                                metric("Req", source.requests)
                                metric("Err", source.errors)
                            }
                        }
                    }
                    .foregroundStyle(tableColor(.sourceBodyText).opacity(0.75))
                }
                .font(sourceFont)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(tableColor(.sourceRowFill))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(source.name), \(source.status), received \(spoken(source.received)), valid \(spoken(source.valid)), requests \(spoken(source.requests)), errors \(spoken(source.errors))")
                .accessibilityIdentifier("source-\(source.name)")
                if source.id != sources.last?.id {
                    Rectangle()
                        .fill(tableColor(.sourceGrid))
                        .frame(height: 1)
                        .accessibilityHidden(true)
                }
            }
        }
    }

    private func metric(_ label: String, _ value: Int?) -> some View {
        Text("\(label) \(value.map { $0.formatted() } ?? "—")")
            .font(metricFont.monospacedDigit())
            .lineLimit(1)
            .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.8)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var sourceFont: Font {
        dynamicTypeSize.isAccessibilitySize ? .body : tableTypography.font(size: max(10, tableTypography.size - 1))
    }

    private var statusFont: Font {
        dynamicTypeSize.isAccessibilitySize ? .body : tableTypography.font(size: max(10, tableTypography.size - 2))
    }

    private var metricFont: Font {
        dynamicTypeSize.isAccessibilitySize ? .caption : tableTypography.font(size: max(10, tableTypography.size - 2))
    }

    private func spoken(_ value: Int?) -> String {
        value.map(String.init) ?? "unavailable"
    }

    private func tableColor(_ role: RadarTableColorRole) -> Color {
        tableColors.color(role, dark: colorScheme == .dark)
    }
}
