import AppKit

/// Descarcă, VERIFICĂ și abia apoi instalează un update, fără browser
/// (Regula 20). Ordinea: manifest (versiune mai nouă, URL permis, SHA-256
/// prezent) → descărcare → `UpdateVerifier` (integritate, semnatar
/// Developer ID Installer, aplicația din pachet: bundle ID, versiune, Team ID)
/// → copie de siguranță a aplicației curente → `installer` cu drepturi de
/// administrator → verificarea versiunii instalate, cu revenire automată la
/// copia de siguranță dacă ceva pică.
///
/// WARNING: promptul de parolă administrator cere interacțiune fizică; pasul
/// de instalare efectivă nu se verifică automat (verificările dinaintea lui da).
enum SelfUpdater {
    private static let log = DiagnosticLog("updater")

    enum UpdateError: LocalizedError {
        case downloadFailed(String)
        case installScriptFailed(String)
        case rejected(UpdateVerifier.Failure)

        var errorDescription: String? {
            switch self {
            case .downloadFailed(let detail):
                return "\(L.t(.updateErrDownload)): \(detail)"
            case .installScriptFailed(let detail):
                return "\(L.t(.updateErrInstall)): \(detail)"
            case .rejected(let failure):
                return Self.describe(failure)
            }
        }

        static func describe(_ failure: UpdateVerifier.Failure) -> String {
            switch failure {
            case .manifestNotNewer(let manifest, let installed):
                return String(format: L.t(.updateErrVersion), manifest, installed)
            case .manifestMissingChecksum: return L.t(.updateErrNoChecksum)
            case .manifestBadURL: return L.t(.updateErrBadURL)
            case .checksumMismatch: return L.t(.updateErrChecksum)
            case .unsignedPackage: return L.t(.updateErrUnsigned)
            case .wrongSigner: return L.t(.updateErrSigner)
            case .payloadMissing, .wrongBundleID, .versionMismatch: return L.t(.updateErrPayload)
            case .appSignatureInvalid: return L.t(.updateErrApp)
            case .toolFailed(let detail): return "\(L.t(.updateErrTool)): \(detail)"
            }
        }
    }

    /// Calea de revenire: ultima aplicație înlocuită, păstrată într-un loc stabil.
    static var rollbackDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Farul/Rollback", isDirectory: true)
    }

    /// Descarcă și verifică, fără să instaleze nimic. Folosit și de proba
    /// `--update-dry-run`: exact aceeași cale ca instalarea reală, până la
    /// promptul de parolă.
    static func downloadAndVerify(pkgURL: URL, version: String, sha256: String?,
                                  installed: String, status: (String) -> Void = { _ in }) async throws -> (pkg: URL, tempDir: URL) {
        guard UpdateVerifier.acceptsDownloadURL(pkgURL) else { throw UpdateError.rejected(.manifestBadURL) }
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("farul-update-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let pkgPath = tempDir.appendingPathComponent("Farul-\(version).pkg")

        status(L.t(.updateDownloading))
        do { try await download(from: pkgURL, to: pkgPath) } catch {
            try? FileManager.default.removeItem(at: tempDir)
            throw error
        }

        status(L.t(.updateVerifying))
        do {
            _ = try UpdateVerifier.verify(pkg: pkgPath, expectedSHA256: sha256, manifestVersion: version,
                                          installedVersion: installed, workDir: tempDir)
        } catch let failure as UpdateVerifier.Failure {
            log.error("Pachet refuzat: \(failure)")
            try? FileManager.default.removeItem(at: tempDir)
            throw UpdateError.rejected(failure)
        }
        return (pkgPath, tempDir)
    }

    @MainActor
    static func downloadAndInstall(pkgURL: URL, version: String, sha256: String?) async {
        let progress = UpdateProgressWindow(version: version)
        progress.show()
        let installed = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
        log.info("Actualizare cerută: \(installed) → \(version)")

        do {
            let (pkgPath, tempDir) = try await downloadAndVerify(
                pkgURL: pkgURL, version: version, sha256: sha256, installed: installed,
                status: { progress.setStatus($0) })

            progress.setStatus(L.t(.updateInstalling))
            try runInstaller(pkgPath: pkgPath, tempDir: tempDir, expectedVersion: version, previousVersion: installed)

            progress.close()
            DiagnosticLog.flush()
            NSApp.terminate(nil)
        } catch {
            progress.close()
            presentFailure(error, fallbackURL: releasesPageURLForFallback)
        }
    }

    // MARK: - Descarcare

    private static func download(from url: URL, to destination: URL) async throws {
        let (tempLocation, response): (URL, URLResponse)
        do {
            (tempLocation, response) = try await URLSession.shared.download(from: url)
        } catch {
            throw UpdateError.downloadFailed(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw UpdateError.downloadFailed("HTTP \(code)")
        }
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: tempLocation, to: destination)
    }

    // MARK: - Instalare (cu copie de siguranță și revenire)

    /// Scriptul rulează ca root, după ieșirea aplicației. Copie de siguranță
    /// înainte de `installer`; dacă instalarea eșuează SAU versiunea de pe disc
    /// nu e cea așteptată, aplicația veche se restaurează.
    static func installScript(pkgPath: String, appPath: String, backupPath: String,
                              expectedVersion: String, userID: uid_t, logPath: String,
                              cleanupPath: String) -> String {
        """
        #!/bin/bash
        exec > "\(logPath)" 2>&1
        APP="\(appPath)"
        BACKUP="\(backupPath)"
        sleep 2
        echo "Copie de siguranta: $BACKUP"
        mkdir -p "$(dirname "$BACKUP")"
        if [ -d "$APP" ]; then rm -rf "$BACKUP"; ditto "$APP" "$BACKUP"; fi
        echo "Instalez actualizarea..."
        installer -pkg "\(pkgPath)" -target /
        status=$?
        installed=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist" 2>/dev/null)
        if [ $status -ne 0 ] || [ "$installed" != "\(expectedVersion)" ]; then
            echo "Instalare esuata (cod $status, versiune $installed); revin la copia de siguranta."
            if [ -d "$BACKUP" ]; then rm -rf "$APP"; ditto "$BACKUP" "$APP"; fi
            chown -R \(userID) "$(dirname "$BACKUP")" 2>/dev/null
            [ $status -eq 0 ] && status=70
            exit $status
        fi
        chown -R \(userID) "$(dirname "$BACKUP")" 2>/dev/null
        echo "Pornesc aplicatia actualizata..."
        /bin/launchctl asuser \(userID) /usr/bin/open "$APP"
        rm -rf "\(cleanupPath)"
        """
    }

    private static func runInstaller(pkgPath: URL, tempDir: URL, expectedVersion: String, previousVersion: String) throws {
        let logPath = tempDir.appendingPathComponent("farul_update.log")
        let scriptPath = tempDir.appendingPathComponent("farul_update.sh")
        let backup = rollbackDirectory.appendingPathComponent("Farul-\(previousVersion).app")

        let scriptContent = installScript(
            pkgPath: pkgPath.path, appPath: AppMover.destination.path, backupPath: backup.path,
            expectedVersion: expectedVersion, userID: getuid(), logPath: logPath.path,
            cleanupPath: tempDir.path)
        do {
            try scriptContent.write(to: scriptPath, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptPath.path)
        } catch {
            throw UpdateError.installScriptFailed(error.localizedDescription)
        }

        let escapedPath = scriptPath.path.replacingOccurrences(of: "\"", with: "\\\"")
        let appleScript = "do shell script \"\(escapedPath)\" with administrator privileges"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", appleScript]
        do {
            try process.run()
            log.info("Instalare pornită (jurnal: \(logPath.path)); copie de siguranță: \(backup.path)")
        } catch {
            throw UpdateError.installScriptFailed(error.localizedDescription)
        }
    }

    // MARK: - Eroare

    private static let releasesPageURLForFallback = URL(string: "https://github.com/gordasgdc/farul/releases/latest")!

    @MainActor
    private static func presentFailure(_ error: Error, fallbackURL: URL) {
        log.error("Actualizare eșuată: \(error.localizedDescription)")
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L.t(.updateFailedTitle)
        alert.informativeText = "\(error.localizedDescription)\n\n\(L.t(.updateManualHint))"
        alert.addButton(withTitle: L.t(.updateOpenPage))
        alert.addButton(withTitle: L.t(.ok))
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(fallbackURL)
        }
    }
}

/// Fereastra minimala de progres (AppKit) — text + spinner indeterminat.
@MainActor
final class UpdateProgressWindow {
    private let window: NSWindow
    private let statusLabel: NSTextField
    private let spinner: NSProgressIndicator

    init(version: String) {
        let contentRect = NSRect(x: 0, y: 0, width: 360, height: 110)
        window = NSWindow(
            contentRect: contentRect,
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.title = L.t(.updateWindowTitle)
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.center()

        let container = NSView(frame: contentRect)

        let titleLabel = NSTextField(labelWithString: "Farul \(version)")
        titleLabel.font = .boldSystemFont(ofSize: 13)
        titleLabel.frame = NSRect(x: 20, y: 70, width: 320, height: 20)
        container.addSubview(titleLabel)

        statusLabel = NSTextField(labelWithString: "")
        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byWordWrapping
        statusLabel.maximumNumberOfLines = 2
        statusLabel.frame = NSRect(x: 20, y: 30, width: 320, height: 34)
        container.addSubview(statusLabel)

        spinner = NSProgressIndicator(frame: NSRect(x: 20, y: 12, width: 320, height: 6))
        spinner.style = .bar
        spinner.isIndeterminate = true
        spinner.startAnimation(nil)
        container.addSubview(spinner)

        window.contentView = container
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func setStatus(_ text: String) {
        statusLabel.stringValue = text
    }

    func close() {
        spinner.stopAnimation(nil)
        window.close()
    }
}
