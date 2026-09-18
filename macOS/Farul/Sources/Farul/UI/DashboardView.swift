import SwiftUI

/// Panoul principal. Grilă adaptivă: pe o fereastră îngustă cardurile se
/// așază pe o coloană, pe una lată pe două — fără puncte de rupere
/// hardcodate, fiindcă fereastra e liber redimensionabilă (Regula 18).
struct DashboardView: View {
    @ObservedObject private var sampler = SystemSampler.shared
    @ObservedObject private var localization = LocalizationManager.shared

    private let columns = [GridItem(.adaptive(minimum: 300, maximum: 460), spacing: 14)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 14) {
                CPUCard(sample: sampler.cpu, history: sampler.cpuHistory)
                MemoryCard(sample: sampler.memory, history: sampler.memoryHistory)
                NetworkCard(sample: sampler.network,
                            download: sampler.downloadHistory,
                            upload: sampler.uploadHistory)
                DiskCard(sample: sampler.disks)
                if sampler.battery.isPresent {
                    BatteryCard(sample: sampler.battery)
                }
                ProcessCard(sample: sampler.processes, sortKey: $sampler.processSort)
            }
            .padding(16)
        }
        .background(VisualEffectView())
        .frame(minWidth: 360, minHeight: 420)
        // Schimbarea limbii nu repornește aplicația: forțăm o reconstrucție
        // a arborelui, altfel textele deja desenate ar rămâne în limba veche.
        .id(localization.current)
    }
}
