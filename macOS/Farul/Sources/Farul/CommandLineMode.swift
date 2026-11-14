import Foundation
import AppKit
import SwiftUI

/// Moduri fără interfață, pentru verificare și suport:
///   Farul --dump-metrics      două eșantionări la 1 s, JSON pe stdout
///   Farul --selftest-sampler  somn/trezire simulate pe ceasul comun
///   Farul --strings <ro|en|es> toate textele aplicației în limba cerută
/// Ies imediat; nu pornesc bara de meniu și nu ating alte setări.
enum CommandLineMode {
    @MainActor
    static func runIfRequested() {
        let args = CommandLine.arguments
        if args.contains("--dump-metrics") { dumpMetrics(); exit(0) }
        if args.contains("--current-language") {
            let manager = LocalizationManager.shared
            print("preference=\(manager.preference.storageValue) current=\(manager.current.rawValue)")
            exit(0)
        }
        if args.contains("--l10n-audit") {
            let missing = LocalizationAudit.incomplete()
            for (key, langs) in missing { print("LIPSĂ \(key.rawValue): \(langs.map(\.rawValue).joined(separator: ","))") }
            print("chei=\(K.allCases.count) incomplete=\(missing.count)")
            exit(missing.isEmpty ? 0 : 1)
        }
        if args.contains("--update-dry-run") {
            Task { @MainActor in
                let result = await UpdateChecker.shared.dryRun()
                print(result.message)
                DiagnosticLog.flush()
                exit(result.ok ? 0 : 2)
            }
            RunLoop.main.run()
        }
        if args.contains("--selftest-sampler") { exit(selfTestSampler() ? 0 : 1) }
        if let i = args.firstIndex(of: "--strings"), i + 1 < args.count, let lang = Lang(rawValue: args[i + 1]) {
            for key in K.allCases { print("\(key.rawValue)\t\(L.t(key, lang))") }
            exit(0)
        }
    }

    /// `Farul --snapshot <png> <ro|en|es> <dark|light|system> [lățime înălțime]`:
    /// deschide panoul real într-o fereastră, lasă graficele să se umple și
    /// îl fotografiază prin `screencapture -l` (materiale reale, fără
    /// automatizare de interfață). Apelat din `applicationDidFinishLaunching`;
    /// rulat din binarul SwiftPM, fără bundle, ca să nu atingă setările
    /// aplicației instalate.
    @MainActor
    static func snapshotIfRequested() -> Bool {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--snapshot"), i + 3 < args.count else { return false }
        let path = args[i + 1]
        let lang = Lang(rawValue: args[i + 2]) ?? .ro
        let theme = AppTheme(rawValue: args[i + 3]) ?? .dark
        let width = i + 4 < args.count ? Double(args[i + 4]) ?? 780 : 780
        let height = i + 5 < args.count ? Double(args[i + 5]) ?? 860 : 860
        NSApp.setActivationPolicy(.accessory)
        LocalizationManager.shared.set(.fixed(lang))
        ThemeManager.shared.set(theme)
        let window = NSWindow(contentRect: NSRect(x: 80, y: 80, width: width, height: height),
                              styleMask: [.titled, .closable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.contentView = NSHostingView(rootView: DashboardView().frame(width: width, height: height))
        window.setContentSize(NSSize(width: width, height: height))
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        DispatchQueue.main.asyncAfter(deadline: .now() + 14) {   // ~7 eșantioane la 2 s
            let capture = Process()
            capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            capture.arguments = ["-x", "-o", "-l", String(window.windowNumber), path]
            try? capture.run(); capture.waitUntilExit()
            print("snapshot \(path) status=\(capture.terminationStatus)")
            exit(0)
        }
        return true
    }

    private static func dumpMetrics() {
        let cpu = CPUMonitor(), net = NetworkMonitor(), proc = ProcessMonitor()
        _ = cpu.sample(); _ = net.sample(); _ = proc.sample()
        Thread.sleep(forTimeInterval: 1.0)
        let c = cpu.sample(), n = net.sample(), p = proc.sample(sortedBy: .cpu)
        let m = MemoryMonitor().sample(), d = DiskMonitor().sample(), b = BatteryMonitor().sample()
        let out: [String: Any] = [
            "cpu": ["total": c.total, "user": c.user, "system": c.system, "idle": c.idle,
                    "cores": c.cores.count, "load": [c.loadAverage.0, c.loadAverage.1, c.loadAverage.2]],
            "memory": ["total": m.total, "used": m.used, "cached": m.cached, "free": m.free,
                       "compressed": m.compressed, "wired": m.wired,
                       "swapUsed": m.swapUsed, "swapTotal": m.swapTotal, "pressure": "\(m.pressure)"],
            "network": ["downRate": n.downloadRate, "upRate": n.uploadRate,
                        "totalIn": n.totalIn, "totalOut": n.totalOut,
                        "interfaces": n.interfaces.map { $0.id }],
            "disks": d.volumes.map { ["name": $0.name, "path": $0.id, "total": $0.total, "available": $0.available,
                                      "internal": $0.isInternal] as [String: Any] },
            "battery": ["present": b.isPresent, "charge": b.charge, "charging": b.isCharging,
                        "onAC": b.isOnAC, "cycles": b.cycleCount ?? -1],
            "processes": ["count": p.count,
                          "top": p.entries.prefix(5).map { ["pid": Int($0.pid), "name": $0.name,
                                                             "cpu": $0.cpu, "memory": $0.memory] as [String: Any] }],
        ]
        if let data = try? JSONSerialization.data(withJSONObject: out, options: [.prettyPrinted, .sortedKeys]) {
            print(String(decoding: data, as: UTF8.self))
        }
    }

    @MainActor
    private static func selfTestSampler() -> Bool {
        let sampler = SystemSampler.shared
        let started = sampler.isRunning
        sampler.handleSleep()
        let stoppedOnSleep = !sampler.isRunning
        sampler.handleWake()
        let restartedOnWake = sampler.isRunning
        print("started=\(started) stoppedOnSleep=\(stoppedOnSleep) restartedOnWake=\(restartedOnWake)")
        return started && stoppedOnSleep && restartedOnWake
    }
}
