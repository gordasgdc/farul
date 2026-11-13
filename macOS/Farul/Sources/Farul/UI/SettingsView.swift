import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject private var localization = LocalizationManager.shared
    @ObservedObject private var theme = ThemeManager.shared
    @ObservedObject private var sampler = SystemSampler.shared

    @State private var verbose = DiagnosticLog.verbose

    private func exportDiagnostics() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Farul-diagnostic-\(DiagnosticLog.sessionID).zip"
        panel.allowedContentTypes = [.zip]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let alert = NSAlert()
        do {
            try DiagnosticExporter.export(to: url, settings: [
                "language": localization.preference.storageValue,
                "theme": theme.current.rawValue,
                "refreshInterval": String(sampler.interval),
            ])
            alert.messageText = L.t(.exportDiagnostics)
            alert.informativeText = String(format: L.t(.exportDone), url.path)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            DiagnosticLog("diagnostic").error("Export eșuat: \(error)")
            alert.alertStyle = .warning
            alert.messageText = L.t(.exportFailed)
            alert.informativeText = error.localizedDescription
        }
        alert.addButton(withTitle: L.t(.ok))
        alert.runModal()
    }

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
                    Text(Format.decimal(0.5, places: 1)).font(.caption2)
                } maximumValueLabel: {
                    Text(Format.decimal(5, places: 0)).font(.caption2)
                }
                Text("\(Format.decimal(sampler.interval, places: 1)) \(L.t(.seconds))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(L.t(.diagnostics)) {
                Toggle(L.t(.debugTemporary), isOn: $verbose)
                    .onChange(of: verbose) { DiagnosticLog.setVerbose($0) }
                Text("\(L.t(.sessionID)): \(DiagnosticLog.sessionID) · v\(DiagnosticLog.appVersion)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Button(L.t(.openLogsFolder)) { NSWorkspace.shared.open(DiagnosticLog.directory) }
                Button(L.t(.copySessionID)) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(DiagnosticLog.sessionID, forType: .string)
                }
                Button(L.t(.exportDiagnostics)) { exportDiagnostics() }
            }

            Section(L.t(.uninstallSection)) {
                Button(L.t(.uninstallApp), role: .destructive) { SelfUninstaller.confirmAndUninstall() }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .id(localization.current)
    }
}
