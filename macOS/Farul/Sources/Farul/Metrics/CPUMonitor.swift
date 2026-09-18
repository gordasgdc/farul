import Foundation
import Darwin

/// Utilizarea procesorului, total și per nucleu.
///
/// macOS nu expune „procent de CPU” — expune CONTORI cumulativi de tick-uri
/// petrecute în fiecare stare (user/system/nice/idle), de la pornire. Un
/// procent are sens doar ca diferență între două citiri, împărțită la
/// totalul tick-urilor din acel interval. De aceea prima eșantionare nu
/// produce niciun număr: n-are cu ce să se compare.
final class CPUMonitor {

    struct Core: Identifiable {
        let id: Int
        let user: Double
        let system: Double
        let idle: Double
        var busy: Double { 1.0 - idle }
    }

    struct Sample {
        let total: Double          // 0…1
        let user: Double
        let system: Double
        let idle: Double
        let cores: [Core]
        let loadAverage: (Double, Double, Double)

        static let zero = Sample(total: 0, user: 0, system: 0, idle: 1,
                                 cores: [], loadAverage: (0, 0, 0))
    }

    /// Tick-urile din citirea precedentă, per nucleu.
    private var previous: [[UInt32]] = []

    func sample() -> Sample {
        guard let current = readPerCoreTicks() else { return .zero }
        defer { previous = current }

        guard previous.count == current.count, !previous.isEmpty else {
            // Prima citire (sau o schimbare de număr de nuclee, care se
            // întâmplă la trezirea din somn pe unele Mac-uri): o folosim
            // doar ca referință.
            return .zero
        }

        var cores: [Core] = []
        var sumUser = 0.0, sumSystem = 0.0, sumIdle = 0.0

        for index in current.indices {
            let now = current[index]
            let before = previous[index]

            // `UInt32` se rotește la ~497 de zile de uptime pe un nucleu.
            // Scăderea cu &- dă diferența corectă chiar și peste rotire;
            // o scădere obișnuită ar produce un număr uriaș și un vârf fals.
            let dUser   = Double(now[Int(CPU_STATE_USER)]   &- before[Int(CPU_STATE_USER)])
            let dSystem = Double(now[Int(CPU_STATE_SYSTEM)] &- before[Int(CPU_STATE_SYSTEM)])
            let dNice   = Double(now[Int(CPU_STATE_NICE)]   &- before[Int(CPU_STATE_NICE)])
            let dIdle   = Double(now[Int(CPU_STATE_IDLE)]   &- before[Int(CPU_STATE_IDLE)])

            let total = dUser + dSystem + dNice + dIdle
            guard total > 0 else {
                cores.append(Core(id: index, user: 0, system: 0, idle: 1))
                continue
            }

            // `nice` e tot timp de utilizator, doar cu altă prioritate.
            // Separat nu-i spune nimic nimănui, deci îl adunăm la user.
            let user = (dUser + dNice) / total
            let system = dSystem / total
            let idle = dIdle / total

            cores.append(Core(id: index, user: user, system: system, idle: idle))
            sumUser += user
            sumSystem += system
            sumIdle += idle
        }

        let count = Double(cores.count)
        return Sample(
            total: count > 0 ? (sumUser + sumSystem) / count : 0,
            user: count > 0 ? sumUser / count : 0,
            system: count > 0 ? sumSystem / count : 0,
            idle: count > 0 ? sumIdle / count : 1,
            cores: cores,
            loadAverage: Self.loadAverage()
        )
    }

    /// Numărul de nuclee logice, citit o singură dată.
    static let coreCount: Int = ProcessInfo.processInfo.activeProcessorCount

    // MARK: - Citirea brută

    private func readPerCoreTicks() -> [[UInt32]]? {
        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0

        let result = host_processor_info(mach_host_self(),
                                         PROCESSOR_CPU_LOAD_INFO,
                                         &cpuCount, &info, &infoCount)
        guard result == KERN_SUCCESS, let info else { return nil }

        // Memoria vine de la kernel și TREBUIE eliberată de noi. Fără
        // `defer`, aplicația pierde câțiva kiloocteți la fiecare
        // eșantionare — adică, la o secundă interval, câteva sute de MB
        // pe zi într-o aplicație care se pretinde ușoară.
        defer {
            vm_deallocate(mach_task_self_,
                          vm_address_t(UInt(bitPattern: info)),
                          vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride))
        }

        let states = Int(CPU_STATE_MAX)
        var ticks: [[UInt32]] = []
        ticks.reserveCapacity(Int(cpuCount))

        for cpu in 0..<Int(cpuCount) {
            var core = [UInt32](repeating: 0, count: states)
            for state in 0..<states {
                core[state] = UInt32(bitPattern: info[cpu * states + state])
            }
            ticks.append(core)
        }
        return ticks
    }

    /// Încărcarea medie pe 1, 5 și 15 minute — alt indicator decât
    /// procentul: numărul mediu de procese care AȘTEAPTĂ procesorul.
    /// Un Mac poate fi la 100% și sănătos, sau la 40% cu o coadă lungă.
    private static func loadAverage() -> (Double, Double, Double) {
        var loads = [Double](repeating: 0, count: 3)
        guard getloadavg(&loads, 3) == 3 else { return (0, 0, 0) }
        return (loads[0], loads[1], loads[2])
    }
}
