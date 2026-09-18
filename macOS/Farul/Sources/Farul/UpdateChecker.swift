import AppKit
import Foundation

/// Verifică `update.json` de pe gordas.dev contra versiunii instalate.
///
/// NU e self-update silențios: descarcă și instalează prin `SelfUpdater`,
/// dar utilizatorul apasă butonul și vede fereastra de parolă a sistemului
/// (Regulile 13 și 20). Niciun browser nu se deschide vreodată.
final class UpdateChecker {
    static let shared = UpdateChecker()

    private let updateURL = URL(string: "https://gordas.dev/farul/update.json")!
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
        let mandatory: Bool

        enum CodingKeys: String, CodingKey {
            case version
            case appVersion = "app_version"
            case changes
            case downloadURL = "download_url"
            case mandatory
        }

        var effectiveVersion: String { appVersion ?? version ?? "0.0.0" }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            version = try c.decodeIfPresent(String.self, forKey: .version)
            appVersion = try c.decodeIfPresent(String.self, forKey: .appVersion)
            changes = try c.decodeIfPresent(String.self, forKey: .changes)
            mandatory = try c.decodeIfPresent(Bool.self, forKey: .mandatory) ?? false

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
            case .decode: return "update.json invalid"
            }
        }
    }

    func checkAtLaunch() {
        fetch { [weak self] result in
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

    private func isNewer(_ remote: String) -> Bool {
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
            Task { await SelfUpdater.downloadAndInstall(pkgURL: url, version: info.effectiveVersion) }
        } else {
            UserDefaults.standard.set(info.effectiveVersion, forKey: dismissedKey)
        }
    }

    private func alert(title: String, body: String, style: NSAlert.Style) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = body
        alert.alertStyle = style
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
