import Foundation
import os.log

/// Logul de diagnostic al aplicației (Regulile 25 și 39), port din GDC Firewall.
///
/// Fiecare eveniment ajunge simultan în două locuri:
///   - unified log, subsistemul `dev.gordas.Farul` — `log show`, Console;
///   - `~/Library/Logs/Farul.log` — citibil direct în terminal, o linie
///     per eveniment: `timestamp NIVEL [categorie] mesaj`.
///
/// `scripts/logs.sh` le arată pe amândouă. Nu se loghează parole, chei sau
/// conținut de fișiere.
struct DiagnosticLog {
    enum Level: String {
        case debug = "DEBUG", info = "INFO", warning = "WARN", error = "ERROR"
    }

    static let subsystem = "dev.gordas.Farul"
    /// `FARUL_LOG_DIR` există pentru teste și probe izolate; implicit
    /// `~/Library/Logs` (standardul de observabilitate, secțiunea macOS).
    static let directory: URL = {
        if let override = ProcessInfo.processInfo.environment["FARUL_LOG_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs", isDirectory: true)
    }()
    static let fileURL = directory.appendingPathComponent("Farul.log")
    /// Peste plafon, fișierul devine `Farul.log.1` și se începe unul nou
    /// (Regula 21: nimic nu crește la nesfârșit). Maximum 2 × plafon pe disc.
    static let maxBytes: UInt64 = {
        if let raw = ProcessInfo.processInfo.environment["FARUL_LOG_MAX_BYTES"], let value = UInt64(raw), value > 0 { return value }
        return 5 * 1024 * 1024
    }()

    /// Identificator al sesiunii, în fiecare linie: leagă o eroare arătată
    /// utilizatorului de intrările din log (corelare, standardul de observabilitate).
    static let sessionID = String(UUID().uuidString.prefix(8)).lowercased()
    static let appVersion: String = {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "dev"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "\(short)+\(build)"
    }()

    private static let verboseUntilKey = "Farul.verboseUntil"

    /// Debug temporar și vizibil: activat din Setări pentru o oră, apoi se
    /// stinge singur (nu rămâne pornit după repornire dacă a expirat).
    static var verbose: Bool {
        let until = UserDefaults.standard.double(forKey: verboseUntilKey)
        return until > Date().timeIntervalSince1970
    }

    static func setVerbose(_ on: Bool, duration: TimeInterval = 3600) {
        let until = on ? Date().timeIntervalSince1970 + duration : 0
        UserDefaults.standard.set(until, forKey: verboseUntilKey)
    }

    let category: String
    private let logger: Logger

    init(_ category: String) {
        self.category = category
        logger = Logger(subsystem: Self.subsystem, category: category)
    }

    /// Golește coada de scriere — la oprire, ca ultima linie să ajungă pe disc.
    static func flush() { LogFile.shared.flush() }

    func debug(_ message: String) { write(.debug, message) }
    func info(_ message: String) { write(.info, message) }
    func warning(_ message: String) { write(.warning, message) }
    func error(_ message: String) { write(.error, message) }

    private func write(_ level: Level, _ message: String) {
        // `.public`: e un log de diagnostic local; ascuns ca „<private>” n-ar
        // mai ajuta la nimic în Console.
        switch level {
        case .debug: logger.debug("\(message, privacy: .public)")
        case .info: logger.info("\(message, privacy: .public)")
        case .warning: logger.warning("\(message, privacy: .public)")
        case .error: logger.error("\(message, privacy: .public)")
        }
        guard level != .debug || Self.verbose else { return }
        LogFile.shared.append(level: level, category: category, message: message)
    }
}

/// Scrierea în fișier: o singură coadă serială, ca liniile venite din fire
/// diferite să nu se amestece.
private final class LogFile {
    static let shared = LogFile()

    private let queue = DispatchQueue(label: "dev.gordas.Farul.logfile", qos: .utility)
    private var handle: FileHandle?
    private let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = .current
        return formatter
    }()

    func append(level: DiagnosticLog.Level, category: String, message: String) {
        let date = Date()
        queue.async { [self] in
            let flat = DiagnosticRedactor.redact(message).replacingOccurrences(of: "\n", with: " ⏎ ")
            let tag = level.rawValue.padding(toLength: 5, withPad: " ", startingAt: 0)
            let line = "\(formatter.string(from: date)) \(tag) [\(category)] [v\(DiagnosticLog.appVersion) s:\(DiagnosticLog.sessionID)] \(flat)\n"
            guard let data = line.data(using: .utf8) else { return }
            rotateIfNeeded()
            if handle == nil { open() }
            try? handle?.write(contentsOf: data)
        }
    }

    func flush() {
        queue.sync { try? handle?.synchronize() }
    }

    private func open() {
        let url = DiagnosticLog.fileURL
        // Eșecul loggerului nu are voie să schimbe verdictul operației
        // principale: totul e `try?`; fără handle, linia se pierde, aplicația merge.
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        handle = try? FileHandle(forWritingTo: url)
        _ = try? handle?.seekToEnd()
    }

    private func rotateIfNeeded() {
        let url = DiagnosticLog.fileURL
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? UInt64) ?? 0
        guard size >= DiagnosticLog.maxBytes else { return }
        try? handle?.close()
        handle = nil
        let previous = url.appendingPathExtension("1")
        try? FileManager.default.removeItem(at: previous)
        try? FileManager.default.moveItem(at: url, to: previous)
    }
}
