import AppKit

/// Dezinstalare nativă din aplicație (Regula 46): fără Terminal, fără sudo.
/// Lista fișierelor afectate e aceeași pe care o vede utilizatorul în
/// confirmare și pe care o șterge codul — o singură sursă, `dataPaths`.
enum SelfUninstaller {
    private static let log = DiagnosticLog("uninstall")
    static let bundleID = "dev.gordas.Farul"

    /// Tot ce scrie Farul în contul utilizatorului. `home` e parametru ca
    /// testele să ruleze pe un director izolat, nu pe contul real.
    static func dataPaths(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [URL] {
        let lib = home.appendingPathComponent("Library", isDirectory: true)
        return [
            lib.appendingPathComponent("Application Support/Farul"),          // include Rollback/
            lib.appendingPathComponent("Preferences/\(bundleID).plist"),
            lib.appendingPathComponent("Caches/\(bundleID)"),
            lib.appendingPathComponent("Logs/Farul.log"),
            lib.appendingPathComponent("Logs/Farul.log.1"),
            lib.appendingPathComponent("Saved Application State/\(bundleID).savedState"),
            lib.appendingPathComponent("HTTPStorages/\(bundleID)"),
            lib.appendingPathComponent("HTTPStorages/\(bundleID).binarycookies"),
            lib.appendingPathComponent("WebKit/\(bundleID)"),
        ]
    }

    static func existingPaths(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [URL] {
        dataPaths(home: home).filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// Șterge datele; întoarce erorile per cale (try/catch per fișier, Regula 26).
    @discardableResult
    static func removeData(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [(URL, Error)] {
        var failures: [(URL, Error)] = []
        for url in existingPaths(home: home) {
            do { try FileManager.default.removeItem(at: url) } catch { failures.append((url, error)) }
        }
        return failures
    }

    @MainActor
    static func confirmAndUninstall() {
        let paths = existingPaths().map { $0.path.replacingOccurrences(of: NSHomeDirectory(), with: "~") }
        let list = (paths + [Bundle.main.bundleURL.path]).map { "• \($0)" }.joined(separator: "\n")
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L.t(.uninstallConfirmTitle)
        alert.informativeText = String(format: L.t(.uninstallConfirmBody), list)
        alert.addButton(withTitle: L.t(.uninstallConfirmButton))
        alert.addButton(withTitle: L.t(.cancel))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        perform()
    }

    @MainActor
    private static func perform() {
        log.info("Dezinstalare pornită")
        DiagnosticLog.flush()
        let failures = removeData()
        UserDefaults.standard.removePersistentDomain(forName: bundleID)

        // `cfprefsd` poate rescrie plist-ul la ieșire: un `sh` detașat îl
        // șterge din nou după 2 s.
        let plist = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences/\(bundleID).plist").path
        let cleanup = Process()
        cleanup.executableURL = URL(fileURLWithPath: "/bin/sh")
        cleanup.arguments = ["-c", "sleep 2; rm -f \"\(plist)\""]
        try? cleanup.run()

        // Ieșirea așteaptă răspunsul Coșului: altfel procesul moare înainte ca
        // aplicația să fie mutată.
        NSWorkspace.shared.recycle([Bundle.main.bundleURL]) { _, appError in
            Task { @MainActor in
                if let appError { log.error("Aplicația nu a putut fi mutată la Coș: \(appError.localizedDescription)") }
                if !failures.isEmpty || appError != nil {
                    let alert = NSAlert()
                    alert.alertStyle = .warning
                    alert.messageText = L.t(.uninstallFailedTitle)
                    let detail = failures.map { "\($0.0.path): \($0.1.localizedDescription)" }
                        + [appError?.localizedDescription].compactMap { $0 }
                    alert.informativeText = detail.joined(separator: "\n")
                    alert.addButton(withTitle: L.t(.ok))
                    alert.runModal()
                }
                NSApp.terminate(nil)
            }
        }
    }
}
