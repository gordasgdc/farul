import AppKit
import Foundation

/// Verifică `update.json` de pe gordas.dev contra versiunii instalate.
///
/// NU e self-update silențios: descarcă și instalează prin `SelfUpdater`,
/// dar utilizatorul apasă butonul și vede fereastra de parolă a sistemului
/// (Regulile 13 și 20). Niciun browser nu se deschide vreodată.
final class UpdateChecker {
    static let shared = UpdateChecker()

    private static let publicURL = URL(string: "https://gordas.dev/farul/update.json")!
    /// Canal local de probă: `defaults write dev.gordas.Farul Farul.updateURL http://127.0.0.1:PORT/update.json`.
    /// Acceptat NUMAI pentru localhost; semnătura, SHA-256 și versiunea se verifică la fel.
    private var updateURL: URL {
        let raw = ProcessInfo.processInfo.environment["FARUL_UPDATE_URL"] ?? UserDefaults.standard.string(forKey: "Farul.updateURL")
        if let raw, let url = URL(string: raw),
           url.scheme == "http", ["127.0.0.1", "localhost"].contains(url.host ?? "") {
            return url
        }
        return Self.publicURL
    }
    private let dismissedKey = "Farul.dismissedUpdateVersion"

    /// Manifestul. `version` și `app_version` sunt sinonime: prima e forma
    /// moștenită, păstrată PENTRU TOTDEAUNA (Regula 35) — un client deja
    /// publicat care o decodează ca obligatorie ar eșua tăcut fără ea și ar
    /// rămâne blocat pe „ești la zi”, fără nicio cale de ieșire.
    private struct UpdateInfo: Decodable {
        let version: String?
        let appVersion: String?
        let changes: String?
        let downloadURL: [String: String]
        let sha256: [String: String]
        let mandatory: Bool

        enum CodingKeys: String, CodingKey {
            case version
            case appVersion = "app_version"
            case changes
            case downloadURL = "download_url"
            case sha256
            case mandatory
        }

        var effectiveVersion: String { appVersion ?? version ?? "0.0.0" }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            version = try c.decodeIfPresent(String.self, forKey: .version)
            appVersion = try c.decodeIfPresent(String.self, forKey: .appVersion)
            changes = try c.decodeIfPresent(String.self, forKey: .changes)
            mandatory = try c.decodeIfPresent(Bool.self, forKey: .mandatory) ?? false

            if let dict = try? c.decode([String: String].self, forKey: .sha256) {
                sha256 = dict
            } else if let single = try? c.decode(String.self, forKey: .sha256) {
                sha256 = ["mac": single]
            } else {
                sha256 = [:]
            }

            // `download_url` a fost și string simplu, și dicționar per
            // platformă. Acceptăm ambele: un manifest scris altfel decât
            // ne așteptam nu trebuie să blocheze actualizările.
            if let dict = try? c.decode([String: String].self, forKey: .downloadURL) {
                downloadURL = dict
            } else if let single = try? c.decode(String.self, forKey: .downloadURL) {
                downloadURL = ["mac": single]
            } else {
                downloadURL = [:]
            }
        }
    }

    /// Eșecul se arată ca eșec, niciodată deghizat în „ești la zi”.
    /// Distincția nu e cosmetică: un hiccup de rețea tratat ca „la zi” face
    /// aplicația să mintă utilizatorul exact când există o versiune nouă.
    private enum FetchError: Error, LocalizedError {
        case network(Error)
        case badStatus(Int)
        case decode

        var errorDescription: String? {
            switch self {
            case .network(let e): return e.localizedDescription
            case .badStatus(let code): return "HTTP \(code)"
            case .decode: return L.t(.updateManifestInvalid)
            }
        }
    }

    /// Proba fără interfață: aceeași cale ca „Actualizează acum”, fără instalare.
    /// Întoarce o linie cu verdictul (folosită de `--update-dry-run`).
    func dryRun() async -> (ok: Bool, message: String) {
        let result: Result<UpdateInfo, Error> = await withCheckedContinuation { c in fetch { c.resume(returning: $0) } }
        switch result {
        case .failure(let error): return (false, "manifest: \(error.localizedDescription)")
        case .success(let info):
            let installed = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
            guard isNewer(info.effectiveVersion) else { return (true, "la zi: manifest \(info.effectiveVersion), instalat \(installed)") }
            guard let string = info.downloadURL["mac"], let url = URL(string: string) else { return (false, "manifest fără download_url.mac") }
            do {
                let (pkg, tempDir) = try await SelfUpdater.downloadAndVerify(pkgURL: url, version: info.effectiveVersion,
                                                                             sha256: info.sha256["mac"], installed: installed)
                try? FileManager.default.removeItem(at: tempDir)
                return (true, "ACCEPTAT \(info.effectiveVersion): \(pkg.lastPathComponent) descărcat, integritate, semnatar și versiune verificate (neinstalat)")
            } catch {
                return (false, "REFUZAT: \(error.localizedDescription)")
            }
        }
    }

    func checkAtLaunch() {
        fetch { [weak self] result in
            if case .failure(let error) = result {
                // Eșecul tăcut la pornire se loghează; „n-am putut verifica” ≠ „ești la zi”.
                DiagnosticLog("updater").warning("Verificare la pornire eșuată: \(error.localizedDescription)")
            }
            guard let self, case .success(let info) = result else { return }
            guard self.isNewer(info.effectiveVersion) else { return }
            let dismissed = UserDefaults.standard.string(forKey: self.dismissedKey)
            if info.mandatory || dismissed != info.effectiveVersion {
                self.present(info)
            }
        }
    }

    func checkManually() {
        fetch { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error):
                self.alert(title: L.t(.updateFailed),
                           body: error.localizedDescription,
                           style: .warning)
            case .success(let info):
                if self.isNewer(info.effectiveVersion) {
                    self.present(info)
                } else {
                    self.alert(title: L.t(.upToDate), body: "", style: .informational)
                }
            }
        }
    }

    private func fetch(completion: @escaping (Result<UpdateInfo, Error>) -> Void) {
        // Dublu ocolire de cache: un parametru unic pentru CDN-urile din
        // față (care cache-uiesc pe URL complet) și o politică explicită
        // pentru URLCache-ul din proces. Fără amândouă, o versiune abia
        // publicată poate rămâne invizibilă ore întregi.
        var components = URLComponents(url: updateURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "t", value: String(Int(Date().timeIntervalSince1970)))]

        var request = URLRequest(url: components.url!)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")

        URLSession.shared.dataTask(with: request) { data, response, error in
            let finish: (Result<UpdateInfo, Error>) -> Void = { result in
                DispatchQueue.main.async { completion(result) }
            }
            if let error { return finish(.failure(FetchError.network(error))) }
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                return finish(.failure(FetchError.badStatus(http.statusCode)))
            }
            guard let data, let info = try? JSONDecoder().decode(UpdateInfo.self, from: data) else {
                return finish(.failure(FetchError.decode))
            }
            finish(.success(info))
        }.resume()
    }

    func isNewer(_ remote: String) -> Bool {
        let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
        return Self.semVerCompare(remote, current) > 0
    }

    /// Comparare pe componente, nu lexicală. Un prefix „v” pe o singură
    /// parte ar face ca „v1.5.0” să pară mai mic decât „1.4.0” la o
    /// comparație de șiruri — de aceea e ignorat explicit.
    static func semVerCompare(_ a: String, _ b: String) -> Int {
        func parts(_ s: String) -> [Int] {
            var s = s
            if s.lowercased().hasPrefix("v") { s.removeFirst() }
            return s.split(separator: ".").map { Int($0.prefix(while: \.isNumber)) ?? 0 }
        }
        let pa = parts(a), pb = parts(b)
        for i in 0..<max(pa.count, pb.count) {
            let va = i < pa.count ? pa[i] : 0
            let vb = i < pb.count ? pb[i] : 0
            if va != vb { return va > vb ? 1 : -1 }
        }
        return 0
    }

    private func present(_ info: UpdateInfo) {
        let alert = NSAlert()
        alert.messageText = "\(L.t(.updateAvailable)): \(info.effectiveVersion)"
        alert.informativeText = info.changes ?? ""
        alert.addButton(withTitle: L.t(.updateNow))
        if !info.mandatory { alert.addButton(withTitle: L.t(.updateLater)) }

        if alert.runModal() == .alertFirstButtonReturn,
           let string = info.downloadURL["mac"], let url = URL(string: string) {
            Task { await SelfUpdater.downloadAndInstall(pkgURL: url, version: info.effectiveVersion,
                                                         sha256: info.sha256["mac"]) }
        } else {
            UserDefaults.standard.set(info.effectiveVersion, forKey: dismissedKey)
        }
    }

    private func alert(title: String, body: String, style: NSAlert.Style) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = body
        alert.alertStyle = style
        alert.addButton(withTitle: L.t(.ok))
        alert.runModal()
    }
}
