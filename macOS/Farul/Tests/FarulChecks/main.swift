import Foundation
import AppKit

// Verificări automate fără XCTest (rulează cu `scripts/test.sh`). Fiecare
// `check` tipărește PASS/FAIL; ieșirea e nenulă dacă pică ceva.
var failures = 0
func check(_ name: String, _ ok: Bool, _ detail: String = "") {
    print("\(ok ? "PASS" : "FAIL")  \(name)\(ok || detail.isEmpty ? "" : "  — \(detail)")")
    if !ok { failures += 1 }
}
let fm = FileManager.default
let env = ProcessInfo.processInfo.environment
let tmp = fm.temporaryDirectory.appendingPathComponent("farul-checks-\(UUID().uuidString.prefix(6))")
try? fm.createDirectory(at: tmp, withIntermediateDirectories: true)
defer { try? fm.removeItem(at: tmp) }

// MARK: Redactor
let home = "/Users/exemplu"
let r1 = DiagnosticRedactor.redact("fisier /Users/exemplu/Library/x si mail a.b@exemplu.ro", home: home)
check("redactor: calea personală", !r1.contains("exemplu/Library") && r1.contains("~/Library"), r1)
check("redactor: email", !r1.contains("a.b@") && r1.contains("<email>"), r1)
let token = "abcdefghijklmnopqrstuvwxyz0123456789ABCD"
check("redactor: token lung", DiagnosticRedactor.redact("key=\(token)", home: home).contains("<redacted>"))
check("redactor: text normal neatins", DiagnosticRedactor.redact("Somn: eșantionarea oprită", home: home) == "Somn: eșantionarea oprită")

// MARK: Log: rotație, sesiune, redactare, logger defect
let logDir = ProcessInfo.processInfo.environment["FARUL_LOG_DIR"] ?? ""
check("log: FARUL_LOG_DIR izolat setat de script", !logDir.isEmpty)
let log = DiagnosticLog("test")
for i in 0..<300 { log.info("linia \(i) contact secret@exemplu.ro cheie=\(token)") }
DiagnosticLog.flush()
let main = DiagnosticLog.fileURL, rolled = main.appendingPathExtension("1")
let mainSize = (try? fm.attributesOfItem(atPath: main.path)[.size] as? UInt64) ?? 0
check("log: rotație creează Farul.log.1", fm.fileExists(atPath: rolled.path))
check("log: dimensiune plafonată (≤ plafon + o linie)", mainSize <= DiagnosticLog.maxBytes + 400, "\(mainSize) > \(DiagnosticLog.maxBytes)")
let content = (try? String(contentsOf: main, encoding: .utf8)) ?? ""
check("log: sesiune și versiune în fiecare linie", content.contains("s:\(DiagnosticLog.sessionID)") && content.contains("[v"))
check("log: email și token redactate", !content.contains("secret@") && !content.contains(token))

// Logger defect (director nescriptibil): verificat de scripts/test.sh printr-un proces separat.
if CommandLine.arguments.contains("--log-broken-child") {
    let l = DiagnosticLog("broken"); for i in 0..<50 { l.error("linia \(i)") }; DiagnosticLog.flush(); print("child-done"); exit(0)
}

// MARK: Export diagnostic
let exportLogs = tmp.appendingPathComponent("logs"); try? fm.createDirectory(at: exportLogs, withIntermediateDirectories: true)
try? "2026-01-01 INFO [x] user /Users/cineva/doc.mov token \(token) mail z@y.com\n".write(to: exportLogs.appendingPathComponent("Farul.log"), atomically: true, encoding: .utf8)
try? "video".write(to: exportLogs.appendingPathComponent("film.mov"), atomically: true, encoding: .utf8)
try? "SECRET".write(to: exportLogs.appendingPathComponent("licenta.key"), atomically: true, encoding: .utf8)
let zip = tmp.appendingPathComponent("diag.zip")
do {
    try DiagnosticExporter.export(to: zip, settings: ["language": "ro"], logDirectory: exportLogs)
    let ls = Process(); ls.executableURL = URL(fileURLWithPath: "/usr/bin/unzip"); ls.arguments = ["-Z1", zip.path]
    let pipe = Pipe(); ls.standardOutput = pipe; try ls.run(); ls.waitUntilExit()
    let names = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    check("export: doar log + manifest", names.contains("manifest.json") && names.contains("Farul.log"), names)
    check("export: fără media/credențiale", !names.contains("film.mov") && !names.contains("licenta.key"), names)
    let cat = Process(); cat.executableURL = URL(fileURLWithPath: "/usr/bin/unzip"); cat.arguments = ["-p", zip.path, "Farul-diagnostic/Farul.log"]
    let p2 = Pipe(); cat.standardOutput = p2; try cat.run(); cat.waitUntilExit()
    let logText = String(decoding: p2.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    check("export: conținut redactat", !logText.contains("cineva") && !logText.contains("z@y.com") && !logText.contains(token), logText)
} catch { check("export: rulează", false, "\(error)") }

// MARK: UpdateVerifier — pași puri
check("versiuni: 0.2.0 > 0.1.1", UpdateVerifier.compare("0.2.0", "0.1.1") > 0)
check("versiuni: egale", UpdateVerifier.compare("0.2.0", "v0.2.0") == 0)
check("versiuni: 0.10.0 > 0.9.0 (numeric, nu lexical)", UpdateVerifier.compare("0.10.0", "0.9.0") > 0)
check("URL: https gordas.dev permis", UpdateVerifier.acceptsDownloadURL(URL(string: "https://gordas.dev/farul/Farul-0.2.0.pkg")!))
check("URL: github releases permis", UpdateVerifier.acceptsDownloadURL(URL(string: "https://github.com/gordasgdc/farul/releases/download/v0.2.0/Farul.pkg")!))
check("URL: http extern refuzat", !UpdateVerifier.acceptsDownloadURL(URL(string: "http://gordas.dev/x.pkg")!))
check("URL: alt domeniu refuzat", !UpdateVerifier.acceptsDownloadURL(URL(string: "https://evil.example/Farul.pkg")!))
check("URL: http localhost permis (canal local)", UpdateVerifier.acceptsDownloadURL(URL(string: "http://127.0.0.1:8765/Farul.pkg")!))
let okSig = """
Package "Farul.pkg":
   Status: signed by a developer certificate issued by Apple for distribution
   Certificate Chain:
    1. Developer ID Installer: DUMITRU CRISTINEL GORDAS (8AR6XP8MG7)
"""
let p = UpdateVerifier.parsePkgSignature(okSig)
check("semnătură: Team ID extras", p.signed && p.team == "8AR6XP8MG7", "\(p)")
check("semnătură: fără semnătură", !UpdateVerifier.parsePkgSignature("Package \"x.pkg\":\n   Status: no signature").signed)
check("semnătură: alt Team ID detectat", UpdateVerifier.parsePkgSignature(okSig.replacingOccurrences(of: "8AR6XP8MG7", with: "ZZZZZZZZZZ")).team == "ZZZZZZZZZZ")

// MARK: UpdateVerifier — pachete reale (din script)
if let valid = env["FARUL_TEST_PKG"], let version = env["FARUL_TEST_PKG_VERSION"] {
    let pkg = URL(fileURLWithPath: valid)
    let sha = (try? UpdateVerifier.sha256(of: pkg)) ?? ""
    func outcome(_ pkg: URL, sha: String?, manifest: String, installed: String) -> String {
        do { _ = try UpdateVerifier.verify(pkg: pkg, expectedSHA256: sha, manifestVersion: manifest, installedVersion: installed, workDir: tmp); return "OK" }
        catch let f as UpdateVerifier.Failure { return "\(f)" } catch { return "other: \(error)" }
    }
    check("pachet valid acceptat", outcome(pkg, sha: sha, manifest: version, installed: "0.1.1") == "OK", outcome(pkg, sha: sha, manifest: version, installed: "0.1.1"))
    check("aceeași versiune refuzată", outcome(pkg, sha: sha, manifest: version, installed: version).hasPrefix("manifestNotNewer"))
    check("versiune mai veche în manifest refuzată", outcome(pkg, sha: sha, manifest: "0.0.9", installed: version).hasPrefix("manifestNotNewer"))
    check("fără SHA-256 în manifest refuzat", outcome(pkg, sha: nil, manifest: version, installed: "0.1.1") == "manifestMissingChecksum")
    check("SHA-256 greșit refuzat", outcome(pkg, sha: String(repeating: "0", count: 64), manifest: version, installed: "0.1.1") == "checksumMismatch")
    check("manifest minte despre versiune (payload ≠ manifest)", outcome(pkg, sha: sha, manifest: "9.9.9", installed: "0.1.1").hasPrefix("versionMismatch"))
    let tampered = tmp.appendingPathComponent("tampered.pkg")
    try? fm.copyItem(at: pkg, to: tampered)
    if let h = try? FileHandle(forWritingTo: tampered) { _ = try? h.seekToEnd(); try? h.write(contentsOf: Data([0x00])); try? h.close() }
    check("pachet modificat refuzat (SHA-ul vechi)", outcome(tampered, sha: sha, manifest: version, installed: "0.1.1") == "checksumMismatch")
    if let unsigned = env["FARUL_TEST_PKG_UNSIGNED"] {
        let u = URL(fileURLWithPath: unsigned), us = try? UpdateVerifier.sha256(of: u)
        check("pachet nesemnat refuzat", outcome(u, sha: us, manifest: version, installed: "0.1.1") == "unsignedPackage", outcome(u, sha: us, manifest: version, installed: "0.1.1"))
    }
} else { print("SKIP  verificări pe pachete reale (FARUL_TEST_PKG lipsă)") }

// MARK: Dezinstalare pe home izolat
let fakeHome = tmp.appendingPathComponent("home")
for path in SelfUninstaller.dataPaths(home: fakeHome) {
    try? fm.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
    if path.pathExtension == "plist" || path.pathExtension == "log" || path.pathExtension == "1" || path.pathExtension == "binarycookies" {
        fm.createFile(atPath: path.path, contents: Data("x".utf8))
    } else { try? fm.createDirectory(at: path.appendingPathComponent("sub"), withIntermediateDirectories: true) }
}
let unrelated = fakeHome.appendingPathComponent("Library/Preferences/com.alta.aplicatie.plist")
fm.createFile(atPath: unrelated.path, contents: Data("alta".utf8))
check("dezinstalare: toate căile create sunt găsite", SelfUninstaller.existingPaths(home: fakeHome).count == SelfUninstaller.dataPaths(home: fakeHome).count)
check("dezinstalare: toate sub Library", SelfUninstaller.dataPaths(home: fakeHome).allSatisfy { $0.path.hasPrefix(fakeHome.path + "/Library/") })
let fails = SelfUninstaller.removeData(home: fakeHome)
check("dezinstalare: șterge tot, fără erori", fails.isEmpty && SelfUninstaller.existingPaths(home: fakeHome).isEmpty, "\(fails)")
check("dezinstalare: nu atinge alte aplicații", fm.fileExists(atPath: unrelated.path))

// MARK: Scriptul de instalare (copie de siguranță + revenire)
let script = SelfUpdater.installScript(pkgPath: "/tmp/x.pkg", appPath: "/Applications/Farul.app", backupPath: "/tmp/bk/Farul-0.1.1.app",
                                       expectedVersion: "0.2.0", userID: 501, logPath: "/tmp/l.log", cleanupPath: "/tmp/c")
let sh = tmp.appendingPathComponent("s.sh"); try? script.write(to: sh, atomically: true, encoding: .utf8)
let bash = Process(); bash.executableURL = URL(fileURLWithPath: "/bin/bash"); bash.arguments = ["-n", sh.path]
try? bash.run(); bash.waitUntilExit()
check("instalare: script bash valid sintactic", bash.terminationStatus == 0)
check("instalare: copie de siguranță înainte și revenire la eșec", script.range(of: "ditto \"$APP\" \"$BACKUP\"") != nil && script.contains("revin la copia de siguranta"))

print(failures == 0 ? "\nTOATE VERIFICĂRILE AU TRECUT" : "\n\(failures) VERIFICĂRI AU PICAT")
exit(failures == 0 ? 0 : 1)
