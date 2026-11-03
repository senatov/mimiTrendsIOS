import SwiftUI

struct CurrencySettingsView: View {
    @AppStorage("display.currency.v1") private var currency = "EUR"
    @State private var rates: DisplayCurrencyRates?

    private var currencySelection: Binding<String> {
        Binding(get: { currency }, set: { newValue in
            currency = newValue
            UserDefaults.standard.set(true, forKey: "display.currency.initialized.v1")
        })
    }

    var body: some View {
        SettingsPage(title: "Currency", subtitle: "One display currency for market prices and charts") { _ in
            SettingsGroup(title: "Display currency") {
                Picker("Currency", selection: currencySelection) {
                    ForEach(DisplayCurrencyRates.supportedCodes, id: \.self) { code in
                        Text("\(code) · \(Locale.current.localizedString(forCurrencyCode: code) ?? code)")
                            .tag(code)
                    }
                }
                .pickerStyle(.menu)
                Text("The first choice is based on your public IP country. Your selection stays saved and is never replaced by a later location check. No device location permission is used.")
                    .font(.caption)
                    .foregroundStyle(TrendsColors.supportingInk)
                if let rates {
                    Text("Approximate conversions use ECB reference rates dated \(rates.date). Market data remains in its original currency in storage.")
                        .font(.caption)
                        .foregroundStyle(TrendsColors.supportingInk)
                } else {
                    Text("Waiting for ECB reference rates. Converted prices appear when rates are available.")
                        .font(.caption)
                        .foregroundStyle(TrendsColors.supportingInk)
                }
            }
        }
        .task { rates = await DisplayCurrencyService().cached() }
    }
}
