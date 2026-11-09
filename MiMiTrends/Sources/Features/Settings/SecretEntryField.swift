import SwiftUI

struct SecretEntryField: View {
    let title: String
    @Binding var value: String
    @State private var isVisible = false

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if isVisible {
                    TextField(title, text: $value)
                } else {
                    SecureField(title, text: $value)
                }
            }
            .settingsInputEmphasis()
            .lineLimit(1)
            .autocorrectionDisabled()
            .accessibilityLabel(title)

            Button { isVisible.toggle() } label: {
                Image(systemName: isVisible ? "eye.slash" : "eye")
                    .frame(width: 20)
            }
            .buttonStyle(TrendsActionButtonStyle(compact: true))
            .accessibilityLabel(isVisible ? "Hide \(title)" : "Show \(title)")
            .help(isVisible ? "Hide \(title)" : "Show \(title)")
        }
        .onDisappear { isVisible = false }
    }
}
