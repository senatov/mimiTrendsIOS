import Observation
import SwiftUI

@MainActor
@Observable
final class RadarTableTypographyStore {
    static let defaultFontName = "System"

    var fontName: String {
        didSet { defaults.set(fontName, forKey: Self.fontNameKey) }
    }

    var size: Double {
        didSet { defaults.set(size, forKey: Self.fontSizeKey) }
    }

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        fontName = defaults.string(forKey: Self.fontNameKey) ?? Self.defaultFontName
        let storedSize = defaults.double(forKey: Self.fontSizeKey)
        size = storedSize == 0 ? 14 : min(20, max(10, storedSize))
    }

    var font: Font {
        font(size: size)
    }

    func font(size requestedSize: Double) -> Font {
        let name = fontName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty || name.caseInsensitiveCompare(Self.defaultFontName) == .orderedSame
            ? .system(size: requestedSize)
            : .custom(name, size: requestedSize, relativeTo: .body)
    }

    func reset() {
        fontName = Self.defaultFontName
        size = 14
        defaults.removeObject(forKey: Self.fontNameKey)
        defaults.removeObject(forKey: Self.fontSizeKey)
    }

    private static let fontNameKey = "radar.table.font.name.v1"
    private static let fontSizeKey = "radar.table.font.size.v1"
}
