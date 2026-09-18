import Foundation
import Darwin

/// Procesele active, sortate după procesor sau memorie.
///
/// Folosește `libproc` direct, nu `ps`: pornirea unui proces extern la
/// fiecare secundă ar consuma mai mult decât tot restul aplicației la un
/// loc, iar ieșirea lui `ps` e text care se schimbă între versiuni de macOS.
final class ProcessMonitor {

    struct Entry: Identifiable, Hashable {
        let id: pid_t
        let name: String
        let cpu: Double            // 0…1, raportat la UN nucleu
        let memory: UInt64         // octeți rezidenți

        var pid: pid_t { id }
    }

    enum SortKey { case cpu, memory }

    struct Sample {
        let entries: [Entry]
        let count: Int

        static let zero = Sample(entries: [], count: 0)
    }

    /// Timpul CPU cumulat al fiecărui proces la citirea precedentă. Fără el
    /// n-am putea calcula un procent — `proc_pid_rusage` dă total, nu rată.
    private var previousCPUTime: [pid_t: UInt64] = [:]
    private var previousTime: Date?

    /// Câte procese ținem. Un Mac are 400–600; afișarea tuturor ar fi o
    /// listă pe care nimeni n-o citește, iar sortarea lor la fiecare
    /// secundă e muncă degeaba.
    var limit = 12

    func sample(sortedBy key: SortKey = .cpu) -> Sample {
        let now = Date()
        let pids = Self.allPIDs()

        var currentCPUTime: [pid_t: UInt64] = [:]
        currentCPUTime.reserveCapacity(pids.count)

        var entries: [Entry] = []
        entries.reserveCapacity(pids.count)

        let elapsed = previousTime.map { now.timeIntervalSince($0) } ?? 0

        for pid in pids {
            var usage = rusage_info_v4()
            let result = withUnsafeMutablePointer(to: &usage) { pointer in
                pointer.withMemoryRebound(to: Optional<rusage_info_t>.self, capacity: 1) {
                    proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
                }
            }
            // Procesele altui utilizator, sau cele care tocmai au murit,
            // întorc eroare. Le sărim tăcut: un firewall de erori aici ar
            // umple jurnalul cu zeci de linii pe secundă, fără folos.
            guard result == 0 else { continue }

            let cpuTime = usage.ri_user_time + usage.ri_system_time   // nanosecunde
            currentCPUTime[pid] = cpuTime

            var cpu = 0.0
            if elapsed > 0.05, let before = previousCPUTime[pid], cpuTime >= before {
                let delta = Double(cpuTime - before) / 1_000_000_000.0
                cpu = delta / elapsed
            }

            entries.append(Entry(id: pid,
                                 name: Self.name(of: pid),
                                 cpu: cpu,
                                 memory: usage.ri_resident_size))
        }

        previousCPUTime = currentCPUTime
        previousTime = now

        switch key {
        case .cpu: entries.sort { $0.cpu > $1.cpu }
        case .memory: entries.sort { $0.memory > $1.memory }
        }

        return Sample(entries: Array(entries.prefix(limit)), count: entries.count)
    }

    // MARK: - Citirea brută

    private static func allPIDs() -> [pid_t] {
        // Două apeluri: primul află câți octeți trebuie, al doilea umple.
        // Între ele pot apărea procese noi, de aceea alocăm cu marjă —
        // altfel lista s-ar tăia tăcut exact când sistemul e cel mai activ.
        let needed = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard needed > 0 else { return [] }

        let capacity = Int(needed) / MemoryLayout<pid_t>.stride + 32
        var buffer = [pid_t](repeating: 0, count: capacity)
        let written = proc_listpids(UInt32(PROC_ALL_PIDS), 0,
                                    &buffer, Int32(capacity * MemoryLayout<pid_t>.stride))
        guard written > 0 else { return [] }

        let count = Int(written) / MemoryLayout<pid_t>.stride
        return buffer.prefix(count).filter { $0 > 0 }
    }

    private static func name(of pid: pid_t) -> String {
        var buffer = [CChar](repeating: 0, count: Int(2 * MAXCOMLEN) + 1)
        // `proc_name` dă numele scurt (cel din Monitorul de activitate).
        // Calea completă ar fi mai precisă, dar ocupă tot rândul și nu e
        // ce caută cineva care se uită la o listă de procese.
        guard proc_name(pid, &buffer, UInt32(buffer.count)) > 0 else {
            return "pid \(pid)"
        }
        return String(cString: buffer)
    }
}
