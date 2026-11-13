import SwiftUI
import AppKit

@main
struct FarulApp: App {
    @NSApplicationDelegateAdaptor(FarulAppDelegate.self) private var delegate

    init() {
        MainActor.assumeIsolated { CommandLineMode.runIfRequested() }
    }

    var body: some Scene {
        // Aplicația trăiește în bara de meniu (`LSUIElement`). Panoul se
        // deschide la cerere — un monitor de sistem care fură o fereastră
        // la fiecare pornire e un monitor pe care îl închizi.
        MenuBarExtra {
            MenuBarContent()
        } label: {
            MenuBarLabel()
        }

        Window(L.t(.appName), id: "dashboard") {
            DashboardView()
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 760, height: 620)

        Settings {
            SettingsView()
        }
    }
}

final class FarulAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppMover.promptIfNeeded()
        _ = ThemeManager.shared
        _ = LocalizationManager.shared
        _ = SystemSampler.shared
        UpdateChecker.shared.checkAtLaunch()
    }

    /// Somnul/trezirea sunt tratate în `SystemSampler.observeSleepAndWake`.
    func applicationWillTerminate(_ notification: Notification) {
        DiagnosticLog("app").info("Oprire")
        DiagnosticLog.flush()
    }
}
