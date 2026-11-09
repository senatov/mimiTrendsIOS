import SwiftUI

enum SettingsTypography {
    static let pageTitle = Font.system(.title2, design: .rounded).weight(.regular)
    static let sectionTitle = Font.system(.title3, design: .rounded).weight(.regular)
    static let label = Font.system(.body, design: .default).weight(.regular)
    static let url = Font.system(.callout, design: .monospaced).weight(.regular)
}

enum SettingsColors {
    static var url: Color {
        #if os(macOS)
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(red: 0.48, green: 0.83, blue: 0.85, alpha: 1)
                : NSColor(red: 0.02, green: 0.35, blue: 0.40, alpha: 1)
        })
        #else
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.48, green: 0.83, blue: 0.85, alpha: 1)
                : UIColor(red: 0.02, green: 0.35, blue: 0.40, alpha: 1)
        })
        #endif
    }

    static var background: Color {
        #if os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color(uiColor: .systemGroupedBackground)
        #endif
    }

    static var group: Color {
        #if os(macOS)
        Color(nsColor: .controlBackgroundColor)
        #else
        Color(uiColor: .secondarySystemGroupedBackground)
        #endif
    }
}

struct SettingsPage<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: (CGFloat) -> Content

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title).font(SettingsTypography.pageTitle).foregroundStyle(.primary)
                        Text(subtitle).font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    content(geometry.size.width)
                }
                .frame(maxWidth: 1600, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
                .foregroundStyle(.primary)
            }
        }
        .background(SettingsColors.background)
        .navigationTitle(title)
    }
}

struct SettingsGroup<Content: View>: View {
    let title: String
    var compact = false
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 10 : 14) {
            Text(title).font(SettingsTypography.sectionTitle).foregroundStyle(.indigo)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(compact ? 12 : 18)
        .background(SettingsColors.group, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.primary.opacity(0.14), lineWidth: 1)
        }
    }
}

struct SettingsValueRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
            Spacer(minLength: 8)
            Text(value)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(.primary)
        }
        .font(SettingsTypography.label)
    }
}
