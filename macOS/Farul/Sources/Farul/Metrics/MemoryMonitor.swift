import Foundation
import Darwin

/// Memoria, raportată aşa cum o raportează Monitorul de activitate — nu aşa
/// cum ar rezulta dintr-o citire naivă.
///
/// Capcana centrală: „memorie liberă” pe macOS e un număr aproape inutil.
/// Sistemul foloseşte deliberat toată memoria nefolosită pentru cache de
/// fişiere, deci `free` e mereu mic şi nu înseamnă nimic rău. Numărul care
/// contează e **presiunea** (memorie comprimată + paginare), nu cât a rămas
/// liber.
final class MemoryMonitor {

    enum Pressure: Int, Comparable {
        case normal = 0, warning = 1, critical = 2

        static func < (a: Pressure, b: Pressure) -> Bool { a.rawValue < b.rawValue }

        var key: K {
            switch self {
            case .normal: return .pressureNormal
            case .warning: return .pressureWarning
            case .critical: return .pressureCritical
            }
        }
    }

    struct Sample {
        let total: UInt64          // octeți
        let used: UInt64           // „App Memory” + wired + comprimat
        let cached: UInt64         // cache de fişiere — recuperabil instant
        let free: UInt64
        let compressed: UInt64
        let wired: UInt64
        let swapUsed: UInt64
        let swapTotal: UInt64
        let pressure: Pressure

        var usedFraction: Double {
            total > 0 ? Double(used) / Double(total) : 0
        }

        static let zero = Sample(total: 0, used: 0, cached: 0, free: 0,
                                 compressed: 0, wired: 0,
                                 swapUsed: 0, swapTotal: 0, pressure: .normal)
    }

    static let physicalMemory: UInt64 = ProcessInfo.processInfo.physicalMemory

    func sample() -> Sample {
        guard let vm = Self.vmStatistics() else { return .zero }

        let pageSize = UInt64(vm_kernel_page_size)
        let free       = UInt64(vm.free_count) * pageSize
        let active     = UInt64(vm.active_count) * pageSize
        let inactive   = UInt64(vm.inactive_count) * pageSize
        let wired      = UInt64(vm.wire_count) * pageSize
        let compressed = UInt64(vm.compressor_page_count) * pageSize
        let purgeable  = UInt64(vm.purgeable_count) * pageSize
        let external   = UInt64(vm.external_page_count) * pageSize

        // Formula Monitorului de activitate: paginile „externe” (cache de
        // fişiere) şi cele purjabile NU se numără ca folosite — sistemul le
        // poate elibera imediat, fără să întrebe pe nimeni.
        let cached = external + purgeable
        let used = active + inactive + wired + compressed > cached
            ? active + inactive + wired + compressed - cached
            : 0

        let swap = Self.swapUsage()

        return Sample(
            total: Self.physicalMemory,
            used: used,
            cached: cached,
            free: free,
            compressed: compressed,
            wired: wired,
            swapUsed: swap.used,
            swapTotal: swap.total,
            pressure: Self.pressure(compressed: compressed,
                                    total: Self.physicalMemory,
                                    swapUsed: swap.used)
        )
    }

    // MARK: - Presiunea

    /// Praguri alese ca să semnaleze ÎNAINTE ca Mac-ul să înceapă să
    /// încetinească vizibil, nu după. Memoria comprimată e primul semn
    /// real; swap-ul folosit e al doilea şi înseamnă că sistemul a început
    /// deja să scrie pe disc.
    /// Sursa autoritară e nucleul: `kern.memorystatus_vm_pressure_level`
    /// (1 normal, 2 avertisment, 4 critic) — aceeași valoare pe care o
    /// reflectă graficul de presiune din Monitorul de activitate. Pragurile
    /// de mai jos rămân doar rezervă dacă sysctl-ul nu răspunde. Verificat
    /// 2026-11-14: cu 2,6 GB swap nucleul raporta 2 (avertisment), iar
    /// euristica singură spunea „critic”.
    private static func kernelPressure() -> Pressure? {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 else { return nil }
        switch level {
        case 1: return .normal
        case 2: return .warning
        case 4: return .critical
        default: return nil
        }
    }

    private static func pressure(compressed: UInt64, total: UInt64, swapUsed: UInt64) -> Pressure {
        if let level = kernelPressure() { return level }
        guard total > 0 else { return .normal }
        let ratio = Double(compressed) / Double(total)
        if ratio > 0.30 || swapUsed > 2_147_483_648 { return .critical }   // >2 GB swap
        if ratio > 0.15 || swapUsed > 268_435_456 { return .warning }      // >256 MB swap
        return .normal
    }

    // MARK: - Citirea brută

    private static func vmStatistics() -> vm_statistics64? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)

        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        return result == KERN_SUCCESS ? stats : nil
    }

    /// `vm.swapusage` întoarce o structură C, nu un şir — o citim direct,
    /// fără să parsăm textul din `sysctl -n vm.swapusage`, care se schimbă
    /// între versiuni de macOS şi e localizat pe unele sisteme.
    private static func swapUsage() -> (used: UInt64, total: UInt64) {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        var mib: [Int32] = [CTL_VM, VM_SWAPUSAGE]

        guard sysctl(&mib, 2, &usage, &size, nil, 0) == 0 else { return (0, 0) }
        return (usage.xsu_used, usage.xsu_total)
    }
}
