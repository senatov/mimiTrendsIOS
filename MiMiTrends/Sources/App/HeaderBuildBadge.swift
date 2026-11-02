#if os(macOS)
import AppKit
import SwiftUI

struct HeaderBuildBadge: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 20, height: 20)
            Text(AppIdentity.name)
                .font(.body.weight(.light))
            Text("v. \(AppIdentity.version)")
                .font(.subheadline.weight(.light).monospaced())
                .foregroundStyle(.indigo)
        }
        .padding(.horizontal, 12)
        .headerBadgeSurface()
        .help(AppIdentity.windowTitle)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(AppIdentity.windowTitle)
    }
}
#endif
