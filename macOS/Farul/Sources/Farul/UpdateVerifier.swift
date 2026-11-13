import Foundation
import CryptoKit

/// Verificările de dinainte de a înlocui aplicația (Regulile 13, 20, 35, 43):
/// compatibilitate de versiune, integritatea pachetului (SHA-256 din manifest)
/// și identitatea semnatarului (Developer ID Installer + aplicația din
/// pachet, ambele cu Team ID-ul GDC). Fără ele, un manifest sau un CDN
/// compromis ar putea instala orice cu drepturi de administrator.
///
/// Totul e Foundation pur, ca să poată fi testat din linia de comandă
/// (`scripts/test.sh`) fără interfață.
enum UpdateVerifier {
    /// Echipa GDC. NU vine din manifest: un manifest falsificat și-ar
    /// declara singur semnatarul.
    static let teamID = "8AR6XP8MG7"
    static let bundleID = "dev.gordas.Farul"
    static let appName = "Farul.app"

    enum Failure: Error, Equatable {
        case manifestNotNewer(manifest: String, installed: String)
        case manifestMissingChecksum
        case manifestBadURL
        case checksumMismatch
        case unsignedPackage
        case wrongSigner(found: String?)
        case payloadMissing
        case wrongBundleID(found: String?)
        case versionMismatch(payload: String?, manifest: String)
        case appSignatureInvalid
        case toolFailed(String)
    }

    struct Verified: Equatable {
        let version: String
        let sha256: String
    }

    // MARK: - Manifest

    /// Doar HTTPS spre gordas.dev / github.com; HTTP numai spre localhost
    /// (canalul local de probă). Orice altceva e refuzat înainte de descărcare.
    static func acceptsDownloadURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        if url.scheme == "http" { return host == "localhost" || host == "127.0.0.1" }
        guard url.scheme == "https" else { return false }
        return host == "gordas.dev" || host.hasSuffix(".gordas.dev")
            || host == "github.com" || host.hasSuffix(".githubusercontent.com")
    }

    /// Compară pe componente (nu lexical). Același algoritm ca `UpdateChecker`.
    static func compare(_ a: String, _ b: String) -> Int {
        func parts(_ s: String) -> [Int] {
            var s = s
            if s.lowercased().hasPrefix("v") { s.removeFirst() }
            return s.split(separator: ".").map { Int($0.prefix(while: \.isNumber)) ?? 0 }
        }
        let pa = parts(a), pb = parts(b)
        for i in 0..<max(pa.count, pb.count) {
            let va = i < pa.count ? pa[i] : 0, vb = i < pb.count ? pb[i] : 0
            if va != vb { return va > vb ? 1 : -1 }
        }
        return 0
    }

    // MARK: - Pași puri (testabili)

    /// `pkgutil --check-signature`: semnat de un certificat Apple-trusted și
    /// Team ID-ul din „Developer ID Installer: Nume (TEAM)”.
    static func parsePkgSignature(_ output: String) -> (signed: Bool, team: String?) {
        let signed = output.contains("Status: signed by a developer certificate issued by Apple")
            || output.contains("Status: signed by a certificate trusted")
        var team: String?
        if let regex = try? NSRegularExpression(pattern: #"Developer ID Installer: .*\(([A-Z0-9]{10})\)"#),
           let match = regex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)),
           let range = Range(match.range(at: 1), in: output) {
            team = String(output[range])
        }
        return (signed, team)
    }

    static func sha256(of file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            // Buffer fix de 8 MB (Regula 21): pachetul nu intră întreg în RAM.
            let chunk = try autoreleasepool { try handle.read(upToCount: 8 * 1024 * 1024) }
            guard let chunk, !chunk.isEmpty else { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Verificarea completă

    /// Ridică `Failure` la primul pas care pică. `workDir` trebuie să existe;
    /// conținutul expandat se șterge înainte de întoarcere.
    static func verify(pkg: URL, expectedSHA256: String?, manifestVersion: String,
                       installedVersion: String, workDir: URL,
                       teamID: String = UpdateVerifier.teamID) throws -> Verified {
        let log = DiagnosticLog("updater")

        guard compare(manifestVersion, installedVersion) > 0 else {
            throw Failure.manifestNotNewer(manifest: manifestVersion, installed: installedVersion)
        }
        guard let expected = expectedSHA256?.lowercased(), expected.count == 64 else {
            throw Failure.manifestMissingChecksum
        }
        let actual = try sha256(of: pkg)
        guard actual == expected else {
            log.error("SHA-256 diferit: manifest \(expected.prefix(12))… față de \(actual.prefix(12))…")
            throw Failure.checksumMismatch
        }

        let signature = try run("/usr/sbin/pkgutil", ["--check-signature", pkg.path])
        let parsed = parsePkgSignature(signature.output)
        guard parsed.signed else { throw Failure.unsignedPackage }
        guard parsed.team == teamID else { throw Failure.wrongSigner(found: parsed.team) }

        let expanded = workDir.appendingPathComponent("expanded-\(UUID().uuidString.prefix(8))")
        defer { try? FileManager.default.removeItem(at: expanded) }
        let expand = try run("/usr/sbin/pkgutil", ["--expand-full", pkg.path, expanded.path])
        guard expand.status == 0 else { throw Failure.toolFailed("pkgutil --expand-full: \(expand.status)") }

        guard let app = findApp(in: expanded) else { throw Failure.payloadMissing }
        let plist = app.appendingPathComponent("Contents/Info.plist")
        let info = NSDictionary(contentsOf: plist) as? [String: Any]
        let foundBundle = info?["CFBundleIdentifier"] as? String
        guard foundBundle == bundleID else { throw Failure.wrongBundleID(found: foundBundle) }
        let payloadVersion = info?["CFBundleShortVersionString"] as? String
        guard payloadVersion == manifestVersion else {
            throw Failure.versionMismatch(payload: payloadVersion, manifest: manifestVersion)
        }

        // Semnătura aplicației din pachet: lanț Apple + Team ID-ul GDC.
        let requirement = "anchor apple generic and certificate leaf[subject.OU] = \"\(teamID)\""
        let codesign = try run("/usr/bin/codesign", ["--verify", "--strict", "--deep", "-R=\(requirement)", app.path])
        guard codesign.status == 0 else {
            log.error("Semnătura aplicației din pachet respinsă: \(codesign.output.prefix(200))")
            throw Failure.appSignatureInvalid
        }
        log.info("Pachet verificat: versiunea \(manifestVersion), sha256 \(actual.prefix(12))…")
        return Verified(version: manifestVersion, sha256: actual)
    }

    private static func findApp(in root: URL) -> URL? {
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil,
                                                          options: [.skipsHiddenFiles]) else { return nil }
        for case let url as URL in walker where url.lastPathComponent == appName {
            return url
        }
        return nil
    }

    private static func run(_ tool: String, _ args: [String]) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do { try process.run() } catch { throw Failure.toolFailed("\(tool): \(error.localizedDescription)") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }
}
