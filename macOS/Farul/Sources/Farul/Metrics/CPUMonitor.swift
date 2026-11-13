import Foundation
import Darwin

/// Utilizarea procesorului, total Èi per nucleu.
///
/// macOS nu expune âprocent de CPUâ â expune CONTORI cumulativi de tick-uri
/// petrecute Ã®n fiecare stare (user/system/nice/idle), de la pornire. Un
/// procent are sens doar ca diferenÈÄ Ã®ntre douÄ citiri, Ã®mpÄrÈitÄ la
/// totalul tick-urilor din acel interval. De aceea prima eÈantionare nu
/// produce niciun numÄr: n-are cu ce sÄ se compare.
final class CPUMonitor {

    struct Core: Identifiable {
        let id: Int
        let user: Double
        let system: Double
        let idle: Double
        var busy: Double { 1.0 - idle }
    }

    struct Sample {
        let total: Double          // 0â¦1
        let user: Double
        let system: Double
        let idle: Double
        let cores: [Core]
        let loadAverage: (Double, Double, Double)

        static let zero = Sample(total: 0, user: 0, system: 0, idle: 1,
                                 cores: [], loadAverage: (0, 0, 0))
    }

    /// Tick-urile din citirea precedentÄ, per nucleu.
    private var previous: [[UInt32]] = []

    /// După somn, contorii nu mai sunt comparabili cu cei dinainte.
    func resetBaseline() { previous = [] }

    func sample() -> Sample {
        guard let current = readPerCoreTicks() else { return .zero }
        defer { previous = current }

        guard previous.count == current.count, !previous.isEmpty else {
            // Prima citire (sau o schimbare de numÄr de nuclee, care se
            // Ã®ntÃ¢mplÄ la trezirea din somn pe unele Mac-uri): o folosim
            // doar ca referinÈÄ.
            return .zero
        }

        var cores: [Core] = []
        var sumUser = 0.0, sumSystem = 0.0, sumIdle = 0.0

        for index in current.indices {
            let now = current[index]
            let before = previous[index]

            // `UInt32` se roteÈte la ~497 de zile de uptime pe un nucleu.
            // ScÄderea cu &- dÄ diferenÈa corectÄ chiar Èi peste rotire;
            // o scÄdere obiÈnuitÄ ar produce un numÄr uriaÈ Èi un vÃ¢rf fals.
            let dUser   = Double(now[Int(CPU_STATE_USER)]   &- before[Int(CPU_STATE_USER)])
            let dSystem = Double(now[Int(CPU_STATE_SYSTEM)] &- before[Int(CPU_STATE_SYSTEM)])
            let dNice   = Double(now[Int(CPU_STATE_NICE)]   &- before[Int(CPU_STATE_NICE)])
            let dIdle   = Double(now[Int(CPU_STATE_IDLE)]   &- before[Int(CPU_STATE_IDLE)])

            let total = dUser + dSystem + dNice + dIdle
            guard total > 0 else {
                cores.append(Core(id: index, user: 0, system: 0, idle: 1))
                continue
            }

            // `nice` e tot timp de utilizator, doar cu altÄ prioritate.
            // Separat nu-i spune nimic nimÄnui, deci Ã®l adunÄm la user.
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

    /// NumÄrul de nuclee logice, citit o singurÄ datÄ.
    static let coreCount: Int = ProcessInfo.processInfo.activeProcessorCount

    // MARK: - Citirea brutÄ

    private func readPerCoreTicks() -> [[UInt32]]? {
        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0

        let result = host_processor_info(mach_host_self(),
                                         PROCESSOR_CPU_LOAD_INFO,
                                         &cpuCount, &info, &infoCount)
        guard result == KERN_SUCCESS, let info else { return nil }

        // Memoria vine de la kernel Èi TREBUIE eliberatÄ de noi. FÄrÄ
        // `defer`, aplicaÈia pierde cÃ¢Èiva kiloocteÈi la fiecare
        // eÈantionare â adicÄ, la o secundÄ interval, cÃ¢teva sute de MB
        // pe zi Ã®ntr-o aplicaÈie care se pretinde uÈoarÄ.
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

    /// ÃncÄrcarea medie pe 1, 5 Èi 15 minute â alt indicator decÃ¢t
    /// procentul: numÄrul mediu de procese care AÈTEAPTÄ procesorul.
    /// Un Mac poate fi la 100% Èi sÄnÄtos, sau la 40% cu o coadÄ lungÄ.
    private static func loadAverage() -> (Double, Double, Double) {
        var loads = [Double](repeating: 0, count: 3)
        guard getloadavg(&loads, 3) == 3 else { return (0, 0, 0) }
        return (loads[0], loads[1], loads[2])
    }
}
