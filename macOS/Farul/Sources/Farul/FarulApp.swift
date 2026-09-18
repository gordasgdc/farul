import SwiftUI
import AppKit

@main
struct FarulApp: App {
    @NSApplicationDelegateAdaptor(FarulAppDelegate.self) private var delegate

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

    /// Eșantionarea se oprește când Mac-ul adoarme și repornește la trezire.
    /// Fără asta, primul eșantion după trezire ar compara contori separați
    /// de ore de somn și ar arăta un vârf inventat — plus că am trezi
    /// procesorul degeaba.
    func applicationDidResignActive(_ notification: Notification) {}
}
