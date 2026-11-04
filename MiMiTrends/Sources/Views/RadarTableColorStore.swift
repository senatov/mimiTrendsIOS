import Observation
import SwiftUI

enum RadarTableColorRole: String, CaseIterable, Identifiable {
    case signalTableFill, signalHeaderFill, signalHeaderText, signalGrid, signalBodyText, signalMutedText, signalRowFill, signalActionAccent
    case sourceTableFill, sourceHeaderFill, sourceHeaderText, sourceGrid, sourceBodyText, sourceMutedText, sourceRowFill, sourceActionAccent
    case headerFill, headerText, grid, bodyText, mutedText
    case rise, fall, selectedRow, criticalRow
    case sourceActive, sourceAttention, sourceInactive, actionAccent

    var id: String { rawValue }
    var key: String { "radar.table.color.\(rawValue).v1" }

    var title: String {
        switch self {
        case .signalTableFill, .sourceTableFill: "Table background"
        case .signalHeaderFill, .sourceHeaderFill: "Header background"
        case .signalHeaderText, .sourceHeaderText: "Header text"
        case .signalGrid, .sourceGrid: "Row and column lines"
        case .signalBodyText, .sourceBodyText: "Table text"
        case .signalMutedText, .sourceMutedText: "Secondary text"
        case .signalRowFill, .sourceRowFill: "Row background"
        case .signalActionAccent, .sourceActionAccent: "Table actions"
        case .headerFill: "Header background"
        case .headerText: "Header text"
        case .grid: "Row and column lines"
        case .bodyText: "Table text"
        case .mutedText: "Secondary text"
        case .rise: "Rising signals"
        case .fall: "Falling signals"
        case .selectedRow: "Selected signal"
        case .criticalRow: "Rapid drop row"
        case .sourceActive: "Active source"
        case .sourceAttention: "Source needing attention"
        case .sourceInactive: "Inactive source"
        case .actionAccent: "Table actions"
        }
    }

    var defaultHexLight: String {
        switch self {
        case .signalTableFill, .sourceTableFill: "FFFFFF"
        case .signalHeaderFill, .sourceHeaderFill: "EAF4FC"
        case .signalHeaderText, .sourceHeaderText: "233A55"
        case .signalGrid, .sourceGrid: "C5D9ED"
        case .signalBodyText, .sourceBodyText: "17365F"
        case .signalMutedText, .sourceMutedText: "31506B"
        case .signalRowFill, .sourceRowFill: "FFFFFF"
        case .signalActionAccent, .sourceActionAccent: "1379B5"
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
        case .signalTableFill, .sourceTableFill: "20252B"
        case .signalHeaderFill, .sourceHeaderFill: "30465B"
        case .signalHeaderText, .sourceHeaderText: "FFF1BE"
        case .signalGrid, .sourceGrid: "4A6077"
        case .signalBodyText, .sourceBodyText: "F1F7FF"
        case .signalMutedText, .sourceMutedText: "C7D9EB"
        case .signalRowFill, .sourceRowFill: "20252B"
        case .signalActionAccent, .sourceActionAccent: "6BB8EE"
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
        var loaded: [RadarTableColorRole: String] = Dictionary(uniqueKeysWithValues: RadarTableColorRole.allCases.compactMap { role in
            guard let hex = defaults.string(forKey: role.key), RadarColorHex.color(hex) != nil else {
                return nil
            }
            return (role, hex)
        })
        for role in Self.tableSpecificRoles where loaded[role] == nil {
            guard let legacyRole = role.legacyRole, let color = loaded[legacyRole] else { continue }
            loaded[role] = color
            defaults.set(color, forKey: role.key)
        }
        overrides = loaded
    }

    func color(_ role: RadarTableColorRole, dark: Bool) -> Color {
        overrides[role].flatMap(RadarColorHex.color) ?? role.defaultColor(dark: dark)
    }

    func isCustomized(_ role: RadarTableColorRole) -> Bool {
        overrides[role] != nil
    }

    func hexValue(for role: RadarTableColorRole) -> String? {
        overrides[role]
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

    private static let tableSpecificRoles: [RadarTableColorRole] = [
        .signalTableFill, .signalHeaderFill, .signalHeaderText, .signalGrid, .signalBodyText, .signalMutedText, .signalRowFill,
        .signalActionAccent, .sourceTableFill, .sourceHeaderFill, .sourceHeaderText, .sourceGrid, .sourceBodyText, .sourceMutedText,
        .sourceRowFill, .sourceActionAccent
    ]
}

private extension RadarTableColorRole {
    var legacyRole: Self? {
        switch self {
        case .signalHeaderFill, .sourceHeaderFill: .headerFill
        case .signalHeaderText, .sourceHeaderText: .headerText
        case .signalGrid, .sourceGrid: .grid
        case .signalBodyText, .sourceBodyText: .bodyText
        case .signalMutedText, .sourceMutedText: .mutedText
        case .signalActionAccent, .sourceActionAccent: .actionAccent
        default: nil
        }
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
