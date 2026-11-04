import Foundation

enum ControlAppearance {
    #if os(iOS)
    static let buttonFontSize = 17.0
    #else
    static let buttonFontSize = 13.0
    #endif
    static let buttonCornerRadius = 9.0
    static let tabFontSize = 15.0
    static let tabHeight = 29.0
    static let tabBottomRadius = 12.0
    static let tabOpenBackground = "EAF3FC"
    static let tabClosedBackground = "EAEAEA"
    static let tabOpenText = "10243D"
    static let tabClosedText = "929292"
    static let tabDarkOpenBackground = "415A78"
    static let tabDarkClosedBackground = "424A58"
    static let tabDarkOpenText = "F3F7FC"
    static let tabDarkClosedText = "D4DCE8"
}
