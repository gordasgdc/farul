import SwiftUI

struct AboutView: View {
    @ObservedObject private var localization = LocalizationManager.shared

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "light.beacon.max")
                .font(.system(size: 44))
                .foregroundStyle(.tint)

            Text(L.t(.appName)).font(.title2.weight(.semibold))
            Text(L.t(.appTagline)).font(.callout).foregroundStyle(.secondary)
            Text("v\(version)").font(.caption.monospacedDigit()).foregroundStyle(.tertiary)

            Divider().padding(.horizontal, 40)

            Text("© 2026 Cristi Gordaș / GDC").font(.caption)
            Link("gordas.dev/farul", destination: URL(string: "https://gordas.dev/farul")!)
                .font(.caption)
        }
        .padding(26)
        .frame(width: 320)
        .background(VisualEffectView())
        .id(localization.current)
    }
}
