import Foundation

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
    static let buttonBorderColor = ""
    static let buttonShadowColor = ""
    static let buttonFontFamily = "System"
    static let buttonTextColor = ""
    static let buttonIconColor = ""
    static let buttonBackgroundColor = ""
}
