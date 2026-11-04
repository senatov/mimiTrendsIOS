#if os(macOS)
import AppKit
import SwiftUI

struct HeaderBuildBadge: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 20, height: 20)
            Text(AppIdentity.name)
                .font(.body.weight(.regular))
            Text("v. \(AppIdentity.version)")
                .font(.subheadline.weight(.regular).monospaced())
                .foregroundStyle(colorScheme == .dark
                    ? Color(red: 0.66, green: 0.79, blue: 0.96)
                    : Color(red: 0.09, green: 0.21, blue: 0.37))
        }
        .padding(.horizontal, 12)
        .headerBadgeSurface()
        .help(AppIdentity.windowTitle)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(AppIdentity.windowTitle)
    }
}
#endif
