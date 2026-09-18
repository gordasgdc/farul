import SwiftUI

struct SettingsView: View {
    @ObservedObject private var localization = LocalizationManager.shared
    @ObservedObject private var theme = ThemeManager.shared
    @ObservedObject private var sampler = SystemSampler.shared

    var body: some View {
        Form {
            Section(L.t(.general)) {
                // Selectorul de limbă e primul: cineva care a deschis
                // Setările fiindcă nu înțelege interfața trebuie să-l
                // găsească fără să citească restul.
                Picker(L.t(.language), selection: Binding(
                    get: { localization.preference },
                    set: { localization.set($0) }
                )) {
                    Text(L.t(.followSystem)).tag(LangPreference.system)
                    Divider()
                    ForEach(Lang.allCases) { lang in
                        Text(lang.nativeName).tag(LangPreference.fixed(lang))
                    }
                }

                Picker(L.t(.theme), selection: Binding(
                    get: { theme.current },
                    set: { theme.set($0) }
                )) {
                    Text(L.t(.themeSystem)).tag(AppTheme.system)
                    Text(L.t(.themeLight)).tag(AppTheme.light)
                    Text(L.t(.themeDark)).tag(AppTheme.dark)
                }
                .pickerStyle(.segmented)
            }

            Section(L.t(.appearance)) {
                // Sub 0.5 s măsurătorile devin zgomot și costul depășește
                // informația; peste 5 s graficele nu mai par vii.
                Slider(value: $sampler.interval, in: 0.5...5.0, step: 0.5) {
                    Text(L.t(.refreshInterval))
                } minimumValueLabel: {
                    Text("0,5").font(.caption2)
                } maximumValueLabel: {
                    Text("5").font(.caption2)
                }
                Text("\(Format.decimal(sampler.interval, places: 1)) \(L.t(.seconds))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .id(localization.current)
    }
}
