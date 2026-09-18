import SwiftUI

// Cardurile. Fiecare primește DOAR eșantionul de care are nevoie, nu tot
// `SystemSampler`-ul: așa un card nu se poate redesena din cauza unei
// metrici pe care nici măcar n-o afișează.

struct CPUCard: View {
    let sample: CPUMonitor.Sample
    let history: History

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                CardHeader(icon: "cpu", title: .cpu,
                           value: Format.percent(sample.total), tint: .blue)

                Sparkline(values: history.values, tint: .blue, ceiling: 1)
                    .frame(height: 34)

                HStack(spacing: 14) {
                    legend(.cpuUser, Format.percent(sample.user), .blue)
                    legend(.cpuSystem, Format.percent(sample.system), .purple)
                    Spacer()
                    Text("\(L.t(.cpuCores)): \(CPUMonitor.coreCount)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if !sample.cores.isEmpty {
                    // Un rând de bare, una per nucleu. Pe un M-series cu 10+
                    // nuclee, aici se vede instant dacă o singură sarcină
                    // ține un nucleu la maxim sau dacă lucrează toate.
                    HStack(spacing: 3) {
                        ForEach(sample.cores) { core in
                            MeterBar(fraction: core.busy, tint: .blue)
                        }
                    }
                    .frame(height: 6)
                }

                Text("\(L.t(.cpuLoadAverage)): "
                     + Format.decimal(sample.loadAverage.0) + " · "
                     + Format.decimal(sample.loadAverage.1) + " · "
                     + Format.decimal(sample.loadAverage.2))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
        }
    }

    private func legend(_ key: K, _ value: String, _ color: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(L.t(key)).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.caption2.monospacedDigit())
        }
    }
}

struct MemoryCard: View {
    let sample: MemoryMonitor.Sample
    let history: History

    private var pressureColor: Color {
        switch sample.pressure {
        case .normal: return .green
        case .warning: return .yellow
        case .critical: return .red
        }
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                CardHeader(icon: "memorychip", title: .memory,
                           value: Format.percent(sample.usedFraction), tint: .orange)

                Sparkline(values: history.values, tint: .orange, ceiling: 1)
                    .frame(height: 34)

                row(.memUsed, Format.bytes(sample.used))
                row(.memCached, Format.bytes(sample.cached))
                row(.memSwap, Format.bytes(sample.swapUsed))

                HStack(spacing: 6) {
                    Text(L.t(.memPressure)).font(.caption2).foregroundStyle(.secondary)
                    Text(L.t(sample.pressure.key))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(pressureColor)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(pressureColor.opacity(0.14), in: Capsule())
                    Spacer()
                    Text(Format.bytes(sample.total))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(14)
        }
    }

    private func row(_ key: K, _ value: String) -> some View {
        HStack {
            Text(L.t(key)).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.caption.monospacedDigit())
        }
    }
}

struct NetworkCard: View {
    let sample: NetworkMonitor.Sample
    let download: History
    let upload: History

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                CardHeader(icon: "network", title: .network,
                           value: sample.busiest?.id ?? L.t(.netNoTraffic), tint: .teal)

                // Cele două grafice împart aceeași scară: altfel un upload
                // de 50 KB/s ar părea, vizual, egal cu un download de
                // 50 MB/s, ceea ce e exact invers față de realitate.
                let ceiling = max(download.maximum, upload.maximum, 1)

                VStack(spacing: 6) {
                    rateRow(.netDownload, sample.downloadRate, download, .teal, ceiling, "arrow.down")
                    rateRow(.netUpload, sample.uploadRate, upload, .indigo, ceiling, "arrow.up")
                }

                HStack {
                    Text("\(L.t(.netTotalDown)): \(Format.bytes(sample.totalIn))")
                    Spacer()
                    Text("\(L.t(.netTotalUp)): \(Format.bytes(sample.totalOut))")
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
            }
            .padding(14)
        }
    }

    private func rateRow(_ key: K, _ rate: Double, _ history: History,
                         _ color: Color, _ ceiling: Double, _ icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.caption2).foregroundStyle(color).frame(width: 12)
            Text(Format.rate(rate))
                .font(.caption.monospacedDigit())
                .frame(width: 84, alignment: .leading)
            Sparkline(values: history.values, tint: color, ceiling: ceiling)
                .frame(height: 22)
        }
        .accessibilityLabel("\(L.t(key)) \(Format.rate(rate))")
    }
}

struct DiskCard: View {
    let sample: DiskMonitor.Sample

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                CardHeader(icon: "internaldrive", title: .disks,
                           value: sample.boot.map { Format.percent($0.usedFraction) },
                           tint: .mint)

                if sample.volumes.isEmpty {
                    Text(L.t(.diskNoVolumes))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(sample.volumes) { volume in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Image(systemName: volume.isRemovable ? "externaldrive" : "internaldrive")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text(volume.name).font(.caption.weight(.medium)).lineLimit(1)
                                Spacer()
                                Text("\(Format.bytes(volume.available)) \(L.t(.diskFree))")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            MeterBar(fraction: volume.usedFraction)
                        }
                    }
                }
            }
            .padding(14)
        }
    }
}

struct BatteryCard: View {
    let sample: BatteryMonitor.Sample

    private var icon: String {
        if !sample.isPresent { return "powerplug" }
        if sample.isCharging { return "battery.100.bolt" }
        switch sample.charge {
        case ..<0.15: return "battery.0"
        case ..<0.45: return "battery.25"
        case ..<0.80: return "battery.75"
        default: return "battery.100"
        }
    }

    private var tint: Color {
        guard sample.isPresent, !sample.isCharging else { return .green }
        switch sample.charge {
        case ..<0.15: return .red
        case ..<0.30: return .yellow
        default: return .green
        }
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                CardHeader(icon: icon, title: .battery,
                           value: sample.isPresent ? Format.percent(sample.charge) : nil,
                           tint: tint)

                if !sample.isPresent {
                    // Un Mac de birou n-are baterie. Cardul spune asta, nu
                    // arată „0%” — care ar suna a defecțiune.
                    Text(L.t(.batteryNone)).font(.caption).foregroundStyle(.secondary)
                } else {
                    MeterBar(fraction: sample.charge, tint: tint)

                    HStack {
                        Text(L.t(sample.isCharging ? .batteryCharging
                                  : (sample.isOnAC ? .batteryOnAC : .batteryOnBattery)))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if let minutes = sample.minutesRemaining {
                            Text("\(L.t(sample.isCharging ? .batteryTimeToFull : .batteryTimeLeft)): "
                                 + Format.duration(minutes: minutes))
                                .font(.caption.monospacedDigit())
                        } else if !sample.isOnAC {
                            Text(L.t(.batteryCalculating))
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }

                    HStack {
                        if let cycles = sample.cycleCount {
                            Text("\(L.t(.batteryCycles)): \(cycles)")
                        }
                        Spacer()
                        if let health = sample.healthFraction {
                            Text("\(L.t(.batteryHealth)): \(Format.percent(health))")
                        }
                    }
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
                }
            }
            .padding(14)
        }
    }
}

struct ProcessCard: View {
    let sample: ProcessMonitor.Sample
    @Binding var sortKey: ProcessMonitor.SortKey

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    CardHeader(icon: "list.bullet.rectangle", title: .processes,
                               value: "\(sample.count)", tint: .pink)
                }

                Picker(L.t(.processTopBy), selection: $sortKey) {
                    Text(L.t(.sortByCPU)).tag(ProcessMonitor.SortKey.cpu)
                    Text(L.t(.sortByMemory)).tag(ProcessMonitor.SortKey.memory)
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                ForEach(sample.entries) { entry in
                    HStack(spacing: 8) {
                        Text(entry.name)
                            .font(.caption)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 8)
                        Text(Format.percent(entry.cpu))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 44, alignment: .trailing)
                        Text(Format.bytes(entry.memory))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 66, alignment: .trailing)
                    }
                }
            }
            .padding(14)
        }
    }
}
