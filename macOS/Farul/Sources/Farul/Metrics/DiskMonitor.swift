import Foundation

/// Spațiul pe volumele montate.
final class DiskMonitor {

    struct Volume: Identifiable {
        let id: String             // calea de montare
        let name: String
        let total: UInt64
        let available: UInt64
        let isRemovable: Bool
        let isInternal: Bool

        var used: UInt64 { total > available ? total - available : 0 }
        var usedFraction: Double { total > 0 ? Double(used) / Double(total) : 0 }
    }

    struct Sample {
        let volumes: [Volume]
        /// Volumul de pornire — cel care contează pentru 95% dintre
        /// întrebările „mai am loc?”.
        let boot: Volume?

        static let zero = Sample(volumes: [], boot: nil)
    }

    func sample() -> Sample {
        let keys: [URLResourceKey] = [
            .volumeNameKey, .volumeTotalCapacityKey,
            // `forImportantUsage` e cel pe care îl arată și Finder: include
            // spațiul pe care sistemul îl poate elibera purjând fișiere
            // recuperabile. `volumeAvailableCapacityKey` simplu raportează
            // mai puțin și sperie utilizatorul degeaba.
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey,
            .volumeIsRemovableKey, .volumeIsInternalKey,
            .volumeIsBrowsableKey, .volumeIsReadOnlyKey
        ]

        guard let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: keys,
            options: [.skipHiddenVolumes]
        ) else { return .zero }

        var volumes: [Volume] = []
        for url in urls {
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { continue }
            // Volumele nenavigabile sunt instantanee de sistem și partiții
            // ascunse: apar în listă, dar n-au sens pentru un utilizator.
            guard values.volumeIsBrowsable != false else { continue }
            // Imaginile de disc montate (DMG, instalatoare) sunt doar-citire și
            // mereu pline: ar apărea ca disc „plin” în roșu, fără sens.
            guard values.volumeIsReadOnly != true else { continue }
            guard let total = values.volumeTotalCapacity, total > 0 else { continue }

            let available = values.volumeAvailableCapacityForImportantUsage
                .map { UInt64($0) } ?? UInt64(values.volumeAvailableCapacity ?? 0)

            volumes.append(Volume(
                id: url.path,
                name: values.volumeName ?? url.lastPathComponent,
                total: UInt64(total),
                available: available,
                isRemovable: values.volumeIsRemovable ?? false,
                isInternal: values.volumeIsInternal ?? true
            ))
        }

        volumes.sort { $0.total > $1.total }
        return Sample(volumes: volumes, boot: volumes.first { $0.id == "/" } ?? volumes.first)
    }
}
