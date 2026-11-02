import Observation
import SwiftUI

enum RadarTableColorRole: String, CaseIterable, Identifiable {
    case headerFill, headerText, grid, bodyText, mutedText
    case rise, fall, selectedRow, criticalRow
    case sourceActive, sourceAttention, sourceInactive, actionAccent

    var id: String { rawValue }
    var key: String { "radar.table.color.\(rawValue).v1" }

    var title: String {
        switch self {
        case .headerFill: "Header background"
        case .headerText: "Header text"
        case .grid: "Row and column lines"
        case .bodyText: "Table text"
        case .mutedText: "Secondary text"
        case .rise: "Rising signals"
        case .fall: "Falling signals"
        case .selectedRow: "Selected signal"
        case .criticalRow: "Rapid crash row"
        case .sourceActive: "Active source"
        case .sourceAttention: "Source needing attention"
        case .sourceInactive: "Inactive source"
        case .actionAccent: "Table actions"
        }
    }

    var defaultHexLight: String {
        switch self {
        case .headerFill: "EAF4FC"
        case .headerText: "233A55"
        case .grid: "C5D9ED"
        case .bodyText: "17365F"
        case .mutedText: "31506B"
        case .rise: "16874A"
        case .fall: "C4343B"
        case .selectedRow: "E8F2FF"
        case .criticalRow: "FFF1D4"
        case .sourceActive: "22B14C"
        case .sourceAttention: "C67A1F"
        case .sourceInactive: "808080"
        case .actionAccent: "1379B5"
        }
    }

    var defaultHexDark: String {
        switch self {
        case .headerFill: "30465B"
        case .headerText: "FFF1BE"
        case .grid: "4A6077"
        case .bodyText: "F1F7FF"
        case .mutedText: "C7D9EB"
        case .rise: "5DD88A"
        case .fall: "FF7474"
        case .selectedRow: "203951"
        case .criticalRow: "4A3523"
        case .sourceActive: "5DE078"
        case .sourceAttention: "FFBE5D"
        case .sourceInactive: "A0A7AE"
        case .actionAccent: "6BB8EE"
        }
    }

    func defaultColor(dark: Bool) -> Color {
        RadarColorHex.color(dark ? defaultHexDark : defaultHexLight)!
    }
}

@MainActor
@Observable
final class RadarTableColorStore {
    @ObservationIgnored private let defaults: UserDefaults
    private var overrides: [RadarTableColorRole: String]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        overrides = Dictionary(uniqueKeysWithValues: RadarTableColorRole.allCases.compactMap { role in
            guard let hex = defaults.string(forKey: role.key), RadarColorHex.color(hex) != nil else {
                return nil
            }
            return (role, hex)
        })
    }

    func color(_ role: RadarTableColorRole, dark: Bool) -> Color {
        overrides[role].flatMap(RadarColorHex.color) ?? role.defaultColor(dark: dark)
    }

    func isCustomized(_ role: RadarTableColorRole) -> Bool {
        overrides[role] != nil
    }

    func set(_ color: Color, for role: RadarTableColorRole) {
        guard let hex = RadarColorHex.hex(color) else { return }
        defaults.set(hex, forKey: role.key)
        overrides[role] = hex
    }

    func reset(_ role: RadarTableColorRole) {
        defaults.removeObject(forKey: role.key)
        overrides.removeValue(forKey: role)
    }

    func resetAll() {
        for role in RadarTableColorRole.allCases { reset(role) }
    }
}

enum RadarColorHex {
    static func color(_ hex: String) -> Color? {
        let digits = hex.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        return Color(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255,
            opacity: 1
        )
    }

    static func hex(_ color: Color) -> String? {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        #if os(macOS)
        guard let native = NSColor(color).usingColorSpace(.sRGB) else { return nil }
        native.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        #else
        guard UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return nil }
        #endif
        return String(format: "%02X%02X%02X", Int((red * 255).rounded()),
                      Int((green * 255).rounded()), Int((blue * 255).rounded()))
    }
}
