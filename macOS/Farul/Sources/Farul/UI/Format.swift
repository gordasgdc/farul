import Foundation

/// Formatarea numerelor, într-un singur loc.
///
/// Există ca tip, nu ca extensii împrăștiate, fiindcă un monitor de sistem
/// e făcut din numere: dacă fiecare card și-ar formata singur octeții, ar
/// apărea „1,5 GB” într-un loc și „1.50 GB” în altul, iar utilizatorul ar
/// crede că sunt două mărimi diferite.
enum Format {

    /// Octeți, în unitatea potrivită. `countStyle: .file` = baza 1000, ca
    /// în Finder — nu baza 1024. Un disc pe care Finder scrie „500 GB” nu
    /// trebuie să apară aici ca „465 GB”, chiar dacă a doua cifră e cea
    /// „corectă” tehnic: utilizatorul compară cu ce vede în Finder.
    static func bytes(_ value: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        return formatter.string(fromByteCount: Int64(min(value, UInt64(Int64.max))))
    }

    /// Viteză de rețea. Sub un kilooctet pe secundă nu arătăm „0,3 KB/s” —
    /// e zgomot de fond, nu trafic.
    static func rate(_ bytesPerSecond: Double) -> String {
        guard bytesPerSecond >= 1024 else { return "0 KB/s" }
        return bytes(UInt64(bytesPerSecond)) + "/s"
    }

    /// Procent întreg. Fracțiunile de procent la o utilizare care se
    /// schimbă de două ori pe secundă sunt ilizibile.
    static func percent(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))%"
    }

    /// Durată în ore și minute, pentru bateria.
    static func duration(minutes: Int) -> String {
        let hours = minutes / 60
        let rest = minutes % 60
        return hours > 0 ? "\(hours) h \(rest) min" : "\(rest) min"
    }

    static func decimal(_ value: Double, places: Int = 2) -> String {
        String(format: "%.\(places)f", value)
    }
}
