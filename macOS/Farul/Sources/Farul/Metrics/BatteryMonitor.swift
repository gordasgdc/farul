import Foundation
import IOKit.ps
import IOKit

/// Starea bateriei. Pe un Mac de birou nu există baterie — cardul dispare
/// complet, nu arată „0%”.
final class BatteryMonitor {

    struct Sample {
        let isPresent: Bool
        let charge: Double         // 0…1
        let isCharging: Bool
        let isOnAC: Bool
        /// Minute rămase. `nil` cât timp sistemul încă estimează — starea
        /// aia ține câteva minute după deconectare și e distinctă de „zero”.
        let minutesRemaining: Int?
        let cycleCount: Int?
        let healthFraction: Double?   // capacitate maximă / capacitate din fabrică

        static let absent = Sample(isPresent: false, charge: 0, isCharging: false,
                                   isOnAC: true, minutesRemaining: nil,
                                   cycleCount: nil, healthFraction: nil)
    }

    func sample() -> Sample {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef],
              let source = sources.first,
              let info = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any]
        else { return .absent }

        guard let current = info[kIOPSCurrentCapacityKey] as? Int,
              let max = info[kIOPSMaxCapacityKey] as? Int, max > 0
        else { return .absent }

        let state = info[kIOPSPowerSourceStateKey] as? String
        let isOnAC = (state == kIOPSACPowerValue)
        let isCharging = info[kIOPSIsChargingKey] as? Bool ?? false

        // -1 înseamnă „încă estimez”, nu „zero minute”. Confuzia asta e
        // exact motivul pentru care unele aplicații arată „0:00 rămas”
        // pentru câteva secunde după ce scoți încărcătorul.
        let raw = isCharging
            ? info[kIOPSTimeToFullChargeKey] as? Int
            : info[kIOPSTimeToEmptyKey] as? Int
        let minutes = (raw ?? -1) >= 0 ? raw : nil

        let smart = Self.smartBattery()

        return Sample(
            isPresent: true,
            charge: Double(current) / Double(max),
            isCharging: isCharging,
            isOnAC: isOnAC,
            minutesRemaining: minutes,
            cycleCount: smart.cycles,
            healthFraction: smart.health
        )
    }

    /// Ciclurile și starea de sănătate nu sunt expuse de IOPowerSources —
    /// stau în serviciul IOKit `AppleSmartBattery`. Dacă lipsește (Mac fără
    /// baterie, sau o schimbare de nume într-o versiune viitoare de macOS),
    /// întoarcem `nil` și cardul pur și simplu nu arată rândurile alea.
    private static func smartBattery() -> (cycles: Int?, health: Double?) {
        let service = IOServiceGetMatchingService(kIOMainPortDefault,
                                                  IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return (nil, nil) }
        defer { IOObjectRelease(service) }

        func number(_ key: String) -> Int? {
            guard let value = IORegistryEntryCreateCFProperty(
                service, key as CFString, kCFAllocatorDefault, 0
            )?.takeRetainedValue() as? Int else { return nil }
            return value
        }

        let cycles = number("CycleCount")
        let design = number("DesignCapacity")
        let maximum = number("AppleRawMaxCapacity") ?? number("MaxCapacity")

        var health: Double?
        if let design, let maximum, design > 0 {
            health = min(1.0, Double(maximum) / Double(design))
        }
        return (cycles, health)
    }
}
