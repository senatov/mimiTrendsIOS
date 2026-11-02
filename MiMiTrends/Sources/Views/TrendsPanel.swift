import SwiftUI

enum TrendsColors {
    static let ink = Color("Ink")
    static let supportingInk = Color("SupportingInk")

    static var canvas: Color {
        #if os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color(uiColor: .systemGroupedBackground)
        #endif
    }

    static var surface: Color {
        #if os(macOS)
        Color(nsColor: .controlBackgroundColor)
        #else
        Color(uiColor: .secondarySystemGroupedBackground)
        #endif
    }
}

struct TrendsPanel: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        content
            .padding(11)
            .background(TrendsColors.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.primary.opacity(contrast == .increased ? 0.32 : 0.18), lineWidth: 1)
            }
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.20 : 0.075), radius: 6, y: 2)
    }
}

extension View {
    func trendsPanel() -> some View {
        modifier(TrendsPanel())
    }
}
