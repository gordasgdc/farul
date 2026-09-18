import SwiftUI

/// Ce se vede în bara de meniu: două numere, nu un panou. Restul se
/// deschide la clic.
struct MenuBarLabel: View {
    @ObservedObject private var sampler = SystemSampler.shared

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "cpu").font(.system(size: 10))
            Text(Format.percent(sampler.cpu.total))
                .font(.system(size: 11, design: .rounded))
                .monospacedDigit()
        }
    }
}

struct MenuBarContent: View {
    @ObservedObject private var sampler = SystemSampler.shared
    @ObservedObject private var localization = LocalizationManager.shared
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        // Rezumat compact: procesor, memorie, trafic. Suficient cât să nu
        // fie nevoie să deschizi panoul pentru o privire rapidă.
        Text("\(L.t(.cpu)): \(Format.percent(sampler.cpu.total))   "
             + "\(L.t(.memory)): \(Format.percent(sampler.memory.usedFraction))")
        Text("↓ \(Format.rate(sampler.network.downloadRate))   "
             + "↑ \(Format.rate(sampler.network.uploadRate))")

        Divider()

        Button(L.t(.openDashboard)) { openWindow(id: "dashboard") }
            .keyboardShortcut("d")
        Button(L.t(.checkForUpdates)) { UpdateChecker.shared.checkManually() }

        Divider()

        Button(L.t(.quit)) { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
