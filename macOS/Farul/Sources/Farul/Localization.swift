import Foundation
import Combine

/// Limbile pe care Farul le vorbește integral. Nu „principal română, restul
/// pe jumătate” — fiecare cheie există în toate trei, iar testul din
/// `LocalizationAudit` pică build-ul dacă una lipsește.
enum Lang: String, CaseIterable, Identifiable {
    case ro, en, es

    var id: String { rawValue }

    /// Numele limbii scris ÎN acea limbă. Un selector care zice
    /// „Spaniolă / Engleză / Română” în română e inutil exact pentru cine
    /// are nevoie de el.
    var nativeName: String {
        switch self {
        case .ro: return "Română"
        case .en: return "English"
        case .es: return "Español"
        }
    }

    var flagless: String {
        switch self {
        case .ro: return "RO"
        case .en: return "EN"
        case .es: return "ES"
        }
    }
}

/// Preferința utilizatorului: urmează sistemul, sau forțează o limbă.
///
/// Există din același motiv ca selectorul de temă (Regula 18): cineva poate
/// avea macOS în engleză și să vrea aplicația în română, sau invers. A urma
/// orbește sistemul nu e suficient.
enum LangPreference: Equatable, Hashable {
    case system
    case fixed(Lang)

    var storageValue: String {
        switch self {
        case .system: return "system"
        case .fixed(let lang): return lang.rawValue
        }
    }

    init(storageValue: String) {
        if let lang = Lang(rawValue: storageValue) {
            self = .fixed(lang)
        } else {
            self = .system
        }
    }
}

final class LocalizationManager: ObservableObject {
    static let shared = LocalizationManager()

    private static let key = "Farul.language"

    @Published private(set) var preference: LangPreference
    @Published private(set) var current: Lang

    private init() {
        let stored = UserDefaults.standard.string(forKey: Self.key) ?? "system"
        let preference = LangPreference(storageValue: stored)
        self.preference = preference
        self.current = Self.resolve(preference)
    }

    func set(_ preference: LangPreference) {
        UserDefaults.standard.set(preference.storageValue, forKey: Self.key)
        self.preference = preference
        self.current = Self.resolve(preference)
    }

    /// Limba sistemului, redusă la cele trei acoperite. Orice altceva
    /// primește ROMÂNĂ, nu engleză: e limba produsului și a autorului.
    private static func resolve(_ preference: LangPreference) -> Lang {
        switch preference {
        case .fixed(let lang):
            return lang
        case .system:
            let code = Locale.preferredLanguages.first?.prefix(2).lowercased() ?? "ro"
            return Lang(rawValue: String(code)) ?? .ro
        }
    }
}

// MARK: - Cheile

/// Fiecare text vizibil are o cheie aici. Un literal scris direct într-un
/// `Text(...)` nu e o scurtătură, e un bug: nu poate fi tradus și nu poate
/// fi găsit cu `grep` când cineva întreabă „unde scrie asta?”.
enum K: String, CaseIterable {
    // Aplicație
    case appName, appTagline
    // Secțiuni
    case cpu, memory, network, disks, battery, processes
    // CPU
    case cpuUser, cpuSystem, cpuIdle, cpuCores, cpuLoadAverage
    // Memorie
    case memUsed, memFree, memCached, memSwap, memPressure
    case pressureNormal, pressureWarning, pressureCritical
    // Rețea
    case netDownload, netUpload, netTotalDown, netTotalUp, netInterface, netNoTraffic
    // Discuri
    case diskUsed, diskFree, diskTotal, diskNoVolumes
    // Baterie
    case batteryCharge, batteryCharging, batteryOnAC, batteryOnBattery
    case batteryTimeLeft, batteryTimeToFull, batteryCycles, batteryHealth
    case batteryNone, batteryCalculating
    // Procese
    case processName, processCPU, processMemory, processPID, processTopBy
    case sortByCPU, sortByMemory
    // Setări
    case settings, general, appearance, language, theme, followSystem
    case refreshInterval, launchAtLogin, showInMenuBar
    case themeSystem, themeLight, themeDark
    // Meniu
    case openDashboard, checkForUpdates, about, quit
    // Actualizări
    case updateAvailable, updateNow, updateLater, upToDate, updateFailed
    // Mutare în /Applications (AppMover)
    case appMoverTitle, appMoverMessage, appMoverMove, appMoverNotNow, appMoverFailedTitle
    case appMoverFailedMessage, appMoverVersionMismatch, appMoverStillTranslocated, appMoverAccessDenied
    // Diverse
    case unknown, loading, seconds
}

enum L {
    /// Traducerea cheii în limba activă.
    static func t(_ key: K) -> String {
        t(key, LocalizationManager.shared.current)
    }

    /// Varianta explicită — folosită de audit și de documentație, unde
    /// avem nevoie de toate trei deodată.
    static func t(_ key: K, _ lang: Lang) -> String {
        // Română ca ultimă plasă de siguranță: o cheie fără traducere nu
        // trebuie să producă niciodată un text gol pe ecran. Auditul o
        // prinde la build; utilizatorul nu trebuie s-o vadă niciodată.
        table[key]?[lang] ?? table[key]?[.ro] ?? key.rawValue
    }

    static let table: [K: [Lang: String]] = [
        .appName: [.ro: "Farul", .en: "Farul", .es: "Farul"],
        .appTagline: [
            .ro: "Monitor de sistem și rețea",
            .en: "System and network monitor",
            .es: "Monitor de sistema y red"],

        .cpu: [.ro: "Procesor", .en: "Processor", .es: "Procesador"],
        .memory: [.ro: "Memorie", .en: "Memory", .es: "Memoria"],
        .network: [.ro: "Rețea", .en: "Network", .es: "Red"],
        .disks: [.ro: "Discuri", .en: "Disks", .es: "Discos"],
        .battery: [.ro: "Baterie", .en: "Battery", .es: "Batería"],
        .processes: [.ro: "Procese", .en: "Processes", .es: "Procesos"],

        .cpuUser: [.ro: "Utilizator", .en: "User", .es: "Usuario"],
        .cpuSystem: [.ro: "Sistem", .en: "System", .es: "Sistema"],
        .cpuIdle: [.ro: "Inactiv", .en: "Idle", .es: "Inactivo"],
        .cpuCores: [.ro: "Nuclee", .en: "Cores", .es: "Núcleos"],
        .cpuLoadAverage: [.ro: "Încărcare medie", .en: "Load average", .es: "Carga media"],

        .memUsed: [.ro: "Folosită", .en: "Used", .es: "Usada"],
        .memFree: [.ro: "Liberă", .en: "Free", .es: "Libre"],
        .memCached: [.ro: "În cache", .en: "Cached", .es: "En caché"],
        .memSwap: [.ro: "Swap", .en: "Swap", .es: "Swap"],
        .memPressure: [.ro: "Presiune", .en: "Pressure", .es: "Presión"],
        .pressureNormal: [.ro: "Normală", .en: "Normal", .es: "Normal"],
        .pressureWarning: [.ro: "Ridicată", .en: "Elevated", .es: "Elevada"],
        .pressureCritical: [.ro: "Critică", .en: "Critical", .es: "Crítica"],

        .netDownload: [.ro: "Descărcare", .en: "Download", .es: "Descarga"],
        .netUpload: [.ro: "Încărcare", .en: "Upload", .es: "Subida"],
        .netTotalDown: [.ro: "Total primit", .en: "Total received", .es: "Total recibido"],
        .netTotalUp: [.ro: "Total trimis", .en: "Total sent", .es: "Total enviado"],
        .netInterface: [.ro: "Interfață", .en: "Interface", .es: "Interfaz"],
        .netNoTraffic: [.ro: "Fără trafic", .en: "No traffic", .es: "Sin tráfico"],

        .diskUsed: [.ro: "Ocupat", .en: "Used", .es: "Usado"],
        .diskFree: [.ro: "Liber", .en: "Free", .es: "Libre"],
        .diskTotal: [.ro: "Total", .en: "Total", .es: "Total"],
        .diskNoVolumes: [.ro: "Niciun volum montat", .en: "No mounted volumes", .es: "Ningún volumen montado"],

        .batteryCharge: [.ro: "Încărcare", .en: "Charge", .es: "Carga"],
        .batteryCharging: [.ro: "Se încarcă", .en: "Charging", .es: "Cargando"],
        .batteryOnAC: [.ro: "La priză", .en: "On AC power", .es: "Con corriente"],
        .batteryOnBattery: [.ro: "Pe baterie", .en: "On battery", .es: "Con batería"],
        .batteryTimeLeft: [.ro: "Timp rămas", .en: "Time remaining", .es: "Tiempo restante"],
        .batteryTimeToFull: [.ro: "Până la încărcare completă", .en: "Until full", .es: "Hasta carga completa"],
        .batteryCycles: [.ro: "Cicluri", .en: "Cycles", .es: "Ciclos"],
        .batteryHealth: [.ro: "Stare", .en: "Health", .es: "Estado"],
        .batteryNone: [.ro: "Fără baterie", .en: "No battery", .es: "Sin batería"],
        .batteryCalculating: [.ro: "Se calculează…", .en: "Calculating…", .es: "Calculando…"],

        .processName: [.ro: "Proces", .en: "Process", .es: "Proceso"],
        .processCPU: [.ro: "Procesor", .en: "CPU", .es: "CPU"],
        .processMemory: [.ro: "Memorie", .en: "Memory", .es: "Memoria"],
        .processPID: [.ro: "PID", .en: "PID", .es: "PID"],
        .processTopBy: [.ro: "Sortare", .en: "Sort by", .es: "Ordenar por"],
        .sortByCPU: [.ro: "Procesor", .en: "CPU", .es: "CPU"],
        .sortByMemory: [.ro: "Memorie", .en: "Memory", .es: "Memoria"],

        .settings: [.ro: "Setări", .en: "Settings", .es: "Ajustes"],
        .general: [.ro: "General", .en: "General", .es: "General"],
        .appearance: [.ro: "Aspect", .en: "Appearance", .es: "Apariencia"],
        .language: [.ro: "Limbă", .en: "Language", .es: "Idioma"],
        .theme: [.ro: "Temă", .en: "Theme", .es: "Tema"],
        .followSystem: [.ro: "Urmează sistemul", .en: "Follow system", .es: "Seguir el sistema"],
        .refreshInterval: [.ro: "Interval de actualizare", .en: "Refresh interval", .es: "Intervalo de actualización"],
        .launchAtLogin: [.ro: "Pornește la autentificare", .en: "Launch at login", .es: "Abrir al iniciar sesión"],
        .showInMenuBar: [.ro: "Arată în bara de meniu", .en: "Show in menu bar", .es: "Mostrar en la barra de menús"],
        .themeSystem: [.ro: "Sistem", .en: "System", .es: "Sistema"],
        .themeLight: [.ro: "Luminoasă", .en: "Light", .es: "Clara"],
        .themeDark: [.ro: "Întunecată", .en: "Dark", .es: "Oscura"],

        .openDashboard: [.ro: "Deschide panoul", .en: "Open dashboard", .es: "Abrir el panel"],
        .checkForUpdates: [.ro: "Verifică actualizări…", .en: "Check for updates…", .es: "Buscar actualizaciones…"],
        .about: [.ro: "Despre Farul", .en: "About Farul", .es: "Acerca de Farul"],
        .quit: [.ro: "Ieșire", .en: "Quit", .es: "Salir"],

        .updateAvailable: [.ro: "Versiune nouă disponibilă", .en: "A new version is available", .es: "Hay una versión nueva disponible"],
        .updateNow: [.ro: "Actualizează acum", .en: "Update now", .es: "Actualizar ahora"],
        .updateLater: [.ro: "Mai târziu", .en: "Later", .es: "Más tarde"],
        .upToDate: [.ro: "Ești la zi", .en: "You are up to date", .es: "Estás al día"],
        .updateFailed: [.ro: "Nu am putut verifica actualizări", .en: "Could not check for updates", .es: "No se pudo buscar actualizaciones"],

        .appMoverTitle: [
            .ro: "Mutare în Aplicații?",
            .en: "Move to Applications?",
            .es: "¿Mover a Aplicaciones?"],
        .appMoverMessage: [
            .ro: "Farul rulează în afara folderului Aplicații. Pentru stabilitate (actualizări automate, permisiuni corecte), se recomandă mutarea în /Applications.",
            .en: "Farul is running outside the Applications folder. For stability (automatic updates, correct permissions), moving it to /Applications is recommended.",
            .es: "Farul se está ejecutando fuera de la carpeta Aplicaciones. Para mayor estabilidad (actualizaciones automáticas, permisos correctos), se recomienda moverlo a /Applications."],
        .appMoverMove: [
            .ro: "Mută în Aplicații",
            .en: "Move to Applications",
            .es: "Mover a Aplicaciones"],
        .appMoverNotNow: [
            .ro: "Nu acum",
            .en: "Not now",
            .es: "Ahora no"],
        .appMoverFailedTitle: [
            .ro: "Mutare eșuată",
            .en: "Move failed",
            .es: "No se pudo mover"],
        .appMoverFailedMessage: [
            .ro: "Nu am putut muta aplicația automat (%@). Mut-o manual în /Applications din Finder.",
            .en: "The app could not be moved automatically (%@). Move it to /Applications manually in Finder.",
            .es: "No se pudo mover la aplicación automáticamente (%@). Muévela manualmente a /Applications desde el Finder."],
        .appMoverVersionMismatch: [
            .ro: "copia din /Applications are versiunea %@",
            .en: "the copy in /Applications has version %@",
            .es: "la copia en /Applications tiene la versión %@"],
        .appMoverStillTranslocated: [
            .ro: "copia din /Applications a rămas marcată pentru izolare",
            .en: "the copy in /Applications is still marked for isolation",
            .es: "la copia en /Applications sigue marcada para aislamiento"],
        .appMoverAccessDenied: [
            .ro: "acces refuzat",
            .en: "access denied",
            .es: "acceso denegado"],

        .unknown: [.ro: "Necunoscut", .en: "Unknown", .es: "Desconocido"],
        .loading: [.ro: "Se încarcă…", .en: "Loading…", .es: "Cargando…"],
        .seconds: [.ro: "secunde", .en: "seconds", .es: "segundos"],
    ]
}

/// Verificarea care face „trilingv integral” o afirmație verificabilă, nu o
/// intenție. Rulată de `scripts/build_app.sh` înainte de orice build.
enum LocalizationAudit {
    /// Cheile cărora le lipsește cel puțin o limbă.
    static func incomplete() -> [(K, [Lang])] {
        K.allCases.compactMap { key in
            let missing = Lang.allCases.filter { L.table[key]?[$0] == nil }
            return missing.isEmpty ? nil : (key, missing)
        }
    }
}
