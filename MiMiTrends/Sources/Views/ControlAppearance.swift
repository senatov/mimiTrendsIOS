import SwiftUI

enum ControlAppearance {
    #if os(iOS)
    static let buttonFontSize = 17.0
    #else
    static let buttonFontSize = 13.0
    #endif
    static let buttonCornerRadius = 6.0
    static let buttonBorderWidth = 0.5
    static let buttonShadowRadius = 1.0
    static let buttonShadowY = 1.5
    static let buttonBorderColor = "000000"
    static let buttonShadowColor = ""
    static let buttonFontFamily = "System"
    static let buttonTextColor = ""
    static let buttonIconColor = "941100"
    static let buttonBackgroundColor = "FFFFFF"

    static func contrastingTextColor(for backgroundHex: String) -> Color? {
        let digits = backgroundHex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard digits.count == 6, let rgb = UInt32(digits, radix: 16) else { return nil }
        let channels = [16, 8, 0].map { shift -> Double in
            let value = Double((rgb >> shift) & 0xFF) / 255
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        let luminance = 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2]
        return luminance > 0.179 ? .black : .white
    }
}
