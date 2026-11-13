import Foundation
import Darwin

/// Traficul de rețea, per interfață și total.
///
/// La fel ca la procesor, kernelul dă CONTORI cumulativi de octeți, nu o
/// viteză. Viteza e diferența dintre două citiri împărțită la timpul scurs
/// — și trebuie folosit timpul REAL măsurat, nu intervalul nominal al
/// timerului: dacă Mac-ul a dormit sau sistemul a fost încărcat, cele două
/// diferă, iar împărțirea la intervalul nominal produce vârfuri inventate.
final class NetworkMonitor {

    struct Interface: Identifiable {
        let id: String             // numele interfeței, ex. „en0”
        let bytesIn: UInt64
        let bytesOut: UInt64
        let downloadRate: Double   // octeți/secundă
        let uploadRate: Double
    }

    struct Sample {
        let downloadRate: Double
        let uploadRate: Double
        let totalIn: UInt64
        let totalOut: UInt64
        let interfaces: [Interface]
        /// Interfața cu cel mai mult trafic în intervalul curent — cea pe
        /// care o arată cardul compact, ca să nu afișăm o listă de zece
        /// interfețe virtuale pentru un singur Wi-Fi activ.
        let busiest: Interface?

        static let zero = Sample(downloadRate: 0, uploadRate: 0, totalIn: 0,
                                 totalOut: 0, interfaces: [], busiest: nil)
    }

    private var previous: [String: (inBytes: UInt64, outBytes: UInt64)] = [:]
    private var previousTime: Date?

    func resetBaseline() { previous = [:]; previousTime = nil }

    func sample() -> Sample {
        let now = Date()
        let counters = Self.readCounters()
        defer {
            previous = counters
            previousTime = now
        }

        guard let previousTime else { return .zero }
        let elapsed = now.timeIntervalSince(previousTime)
        // Un interval nul sau negativ (ceas mutat, trezire din somn) ar
        // produce o împărțire la ~0 și o viteză absurdă. Sărim eșantionul.
        guard elapsed > 0.05 else { return .zero }

        var interfaces: [Interface] = []
        var totalIn: UInt64 = 0, totalOut: UInt64 = 0
        var downRate = 0.0, upRate = 0.0

        for (name, current) in counters {
            totalIn += current.inBytes
            totalOut += current.outBytes

            guard let before = previous[name] else { continue }
            // Contorii se pot reseta la reconectarea interfeței. O scădere
            // negativă înseamnă reset, nu trafic — o raportăm ca zero, nu
            // ca un vârf de câțiva gigaocteți pe secundă.
            let deltaIn = current.inBytes >= before.inBytes ? current.inBytes - before.inBytes : 0
            let deltaOut = current.outBytes >= before.outBytes ? current.outBytes - before.outBytes : 0

            let down = Double(deltaIn) / elapsed
            let up = Double(deltaOut) / elapsed
            downRate += down
            upRate += up

            interfaces.append(Interface(id: name,
                                        bytesIn: current.inBytes,
                                        bytesOut: current.outBytes,
                                        downloadRate: down,
                                        uploadRate: up))
        }

        interfaces.sort { ($0.downloadRate + $0.uploadRate) > ($1.downloadRate + $1.uploadRate) }

        return Sample(downloadRate: downRate,
                      uploadRate: upRate,
                      totalIn: totalIn,
                      totalOut: totalOut,
                      interfaces: interfaces,
                      busiest: interfaces.first { $0.downloadRate + $0.uploadRate > 0 } ?? interfaces.first)
    }

    // MARK: - Citirea brută

    /// `getifaddrs` cu familia `AF_LINK` — singura care poartă structura
    /// `if_data`, adică octeții. Intrările `AF_INET`/`AF_INET6` dau adrese,
    /// nu contori, și sunt ignorate aici.
    private static func readCounters() -> [String: (inBytes: UInt64, outBytes: UInt64)] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return [:] }
        defer { freeifaddrs(head) }

        var result: [String: (UInt64, UInt64)] = [:]
        var pointer: UnsafeMutablePointer<ifaddrs>? = first

        while let entry = pointer {
            defer { pointer = entry.pointee.ifa_next }

            guard let addr = entry.pointee.ifa_addr,
                  addr.pointee.sa_family == UInt8(AF_LINK) else { continue }

            let name = String(cString: entry.pointee.ifa_name)
            // `lo0` e bucla locală: tot ce trece pe ea nu părăsește Mac-ul.
            // Inclusă în total, ar face ca o copie locală de fișiere să
            // arate ca un download de rețea.
            guard name != "lo0" else { continue }

            guard let data = entry.pointee.ifa_data?.assumingMemoryBound(to: if_data.self) else { continue }
            result[name] = (UInt64(data.pointee.ifi_ibytes), UInt64(data.pointee.ifi_obytes))
        }
        return result
    }
}
