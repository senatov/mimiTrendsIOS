import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

enum RadarSortColumn: String, CaseIterable {
    case company, event, movement, window, price, age

    var title: String {
        switch self {
        case .company: "Company"
        case .event: "Event"
        case .movement: "Move"
        case .window: "Window"
        case .price: "Price"
        case .age: "Age"
        }
    }

    var isNumeric: Bool { self == .movement || self == .window || self == .price || self == .age }

    var minimumWidth: CGFloat {
        switch self {
        case .company: 100
        case .event: 180
        case .movement: 80
        case .window: 90
        case .price: 88
        case .age: 84
        }
    }

    var maximumWidth: CGFloat {
        switch self {
        case .company: 300
        case .event: 280
        case .movement: 120
        case .window: 115
        case .price: 140
        case .age: 110
        }
    }
}

struct RadarSignalColumnWidths {
    let company: CGFloat
    let event: CGFloat
    let movement: CGFloat
    let window: CGFloat
    let price: CGFloat
    let age: CGFloat

    func width(for column: RadarSortColumn) -> CGFloat {
        switch column {
        case .company: company
        case .event: event
        case .movement: movement
        case .window: window
        case .price: price
        case .age: age
        }
    }

    static func fit(
        signals: [ScanResult],
        companyNames: [String],
        currencyRates: DisplayCurrencyRates?,
        displayCurrency: String,
        availableWidth: CGFloat,
        overrides: [RadarSortColumn: CGFloat],
        fontSize: Double
    ) -> Self {
        let contentWidths = Self.contentWidths(
            signals: signals, companyNames: companyNames, currencyRates: currencyRates,
            displayCurrency: displayCurrency, fontSize: fontSize
        )
        var widths = Dictionary(uniqueKeysWithValues: RadarSortColumn.allCases.map { column in
            let fitted = min(max(contentWidths[column] ?? column.minimumWidth, column.minimumWidth), column.maximumWidth)
            let requested = overrides[column] ?? fitted
            return (column, min(max(requested, column.minimumWidth), column.maximumWidth))
        })

        let minimumTableWidth = RadarSortColumn.allCases.reduce(CGFloat.zero) { $0 + $1.minimumWidth }
        var overflow = max(0, widths.values.reduce(0, +) - max(availableWidth, minimumTableWidth))
        for column in RadarSortColumn.allCases {
            guard overflow > 0 else { break }
            let current = widths[column] ?? column.minimumWidth
            let reduction = min(overflow, current - column.minimumWidth)
            widths[column] = current - reduction
            overflow -= reduction
        }

        return Self(
            company: widths[.company] ?? RadarSortColumn.company.minimumWidth,
            event: widths[.event] ?? RadarSortColumn.event.minimumWidth,
            movement: widths[.movement] ?? RadarSortColumn.movement.minimumWidth,
            window: widths[.window] ?? RadarSortColumn.window.minimumWidth,
            price: widths[.price] ?? RadarSortColumn.price.minimumWidth,
            age: widths[.age] ?? RadarSortColumn.age.minimumWidth
        )
    }
    static func contentWidths(
        signals: [ScanResult], companyNames: [String], currencyRates: DisplayCurrencyRates?,
        displayCurrency: String, fontSize: Double
    ) -> [RadarSortColumn: CGFloat] {
        [
            .company: measuredWidth(companyNames, fontSize: fontSize) + 50,
            .event: max(205, measuredWidth(signals.map(eventLabel), fontSize: fontSize) + 108),
            .movement: measuredWidth(signals.map {
                String(format: "%+.2f%%", $0.windowChangePercent)
            }, fontSize: fontSize) + 24,
            .window: measuredWidth(signals.map(\.signalWindowLabel), fontSize: fontSize) + 24,
            .price: measuredWidth(signals.map {
                RadarSignalPrice.display($0, rates: currencyRates, currency: displayCurrency).text
            }, fontSize: fontSize) + 30,
            .age: 70
        ]
    }

    private static func measuredWidth(_ values: [String], fontSize: Double) -> CGFloat {
        #if os(macOS)
        let font = NSFont.systemFont(ofSize: fontSize)
        #else
        let font = UIFont.systemFont(ofSize: fontSize)
        #endif
        return values.prefix(200).map { ($0 as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
    }

    private static func eventLabel(_ signal: ScanResult) -> String {
        let label = RadarSignalPresentation.badge(for: signal)
        return signal.isRetained ? "\(label) · RECENT" : label
    }
}

enum RadarSignalPresentation {
    static func badge(for signal: ScanResult) -> String {
        let label = badge(for: signal.signalSource)
        if signal.dataStatus == YahooCandleSignalPipeline.verifiedStatus { return "\(label) · Y+F" }
        if signal.dataStatus == YahooCandleSignalPipeline.delayedVolumeValidatedStatus {
            return "\(label) · Y delayed"
        }
        if signal.dataStatus == YahooCandleSignalPipeline.volumeValidatedStatus { return "\(label) · Y" }
        return label
    }
    static func title(for source: String) -> String {
        switch source.lowercased() {
        case "rapid crash": "Rapid drop"
        case "rapid rise", "sharp rebound": "Sharp rebound"
        case "sustained drop": "Sustained drop"
        case "sustained rise", "smooth rise": "Smooth rise"
        case "tradable corridor": "Tradable corridor"
        default: source.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    static func badge(for source: String) -> String {
        switch source.lowercased() {
        case "boerse.de price rise": "↑ BOERSE.DE · NO VOLUME"
        case "boerse.de price drop": "↓ BOERSE.DE · NO VOLUME"
        case "l&s quote rise": "↑ L&S QUOTE · NO VOLUME"
        case "l&s quote drop": "↓ L&S QUOTE · NO VOLUME"
        case "rapid crash": "↓ RAPID DROP"
        case "rapid rise", "sharp rebound": "↑ SHARP REBOUND"
        case "sustained drop": "↓ SUSTAINED DROP"
        case "sustained rise", "smooth rise": "↑ SMOOTH RISE"
        case "tradable corridor": "▰ CORRIDOR"
        default: title(for: source).uppercased()
        }
    }
}
