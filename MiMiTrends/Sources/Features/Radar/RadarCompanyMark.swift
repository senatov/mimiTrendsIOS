import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct RadarCompanyMark: View {
    let metadata: RadarCompanyMetadata?
    let name: String
    var size: CGFloat = 18
    var showsPlaceholder = false

    @ViewBuilder var body: some View {
        if let data = metadata?.logoData, let image = decodedLogo(data) {
            image.resizable().scaledToFit()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .accessibilityLabel("\(name) logo")
        } else if showsPlaceholder {
            Image(systemName: "building.2.crop.circle")
                .resizable().scaledToFit()
                .foregroundStyle(.secondary)
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        }
    }

    private func decodedLogo(_ data: Data) -> Image? {
        #if os(macOS)
        guard let image = NSImage(data: data) else { return nil }
        return Image(nsImage: image)
        #else
        guard let image = UIImage(data: data) else { return nil }
        return Image(uiImage: image)
        #endif
    }
}
