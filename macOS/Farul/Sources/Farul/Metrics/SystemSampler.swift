import Foundation
import Combine
import SwiftUI
import AppKit

/// Ceasul comun al aplicației.
///
/// Toate colectoarele sunt eșantionate de AICI, la un singur interval. Șase
/// timere independente ar produce șase treziri diferite ale procesorului în
/// fiecare secundă — exact opusul scopului unei aplicații care se laudă că e
/// ușoară. Un monitor de sistem care încarcă sistemul e o glumă proastă.
@MainActor
final class SystemSampler: ObservableObject {
    static let shared = SystemSampler()

    // MARK: - Stare publicată

    @Published private(set) var cpu = CPUMonitor.Sample.zero
    @Published private(set) var memory = MemoryMonitor.Sample.zero
    @Published private(set) var network = NetworkMonitor.Sample.zero
    @Published private(set) var disks = DiskMonitor.Sample.zero
    @Published private(set) var battery = BatteryMonitor.Sample.absent
    @Published private(set) var processes = ProcessMonitor.Sample.zero

    /// Istoric scurt pentru graficele de tip sparkline. Plafonat explicit:
    /// un istoric nelimitat într-o aplicație care rulează săptămâni întregi
    /// e o scurgere de memorie, nu o funcționalitate (Regula 21).
    @Published private(set) var cpuHistory = History(capacity: 60)
    @Published private(set) var memoryHistory = History(capacity: 60)
    @Published private(set) var downloadHistory = History(capacity: 60)
    @Published private(set) var uploadHistory = History(capacity: 60)

    @Published var processSort: ProcessMonitor.SortKey = .cpu

    /// Intervalul, în secunde. Sub 0.5 s măsurătorile devin zgomot, iar
    /// costul depășește informația.
    @AppStorage("Farul.refreshInterval") var interval: Double = 2.0 {
        didSet { restart() }
    }

    // MARK: - Colectoare

    private let cpuMonitor = CPUMonitor()
    private let memoryMonitor = MemoryMonitor()
    private let networkMonitor = NetworkMonitor()
    private let diskMonitor = DiskMonitor()
    private let batteryMonitor = BatteryMonitor()
    private let processMonitor = ProcessMonitor()

    private var timer: Timer?
    /// Discurile și bateria se schimbă lent. Le citim o dată la câteva
    /// cicluri, nu la fiecare: enumerarea volumelor montate atinge discul,
    /// iar IOKit-ul bateriei e mai scump decât toate celelalte la un loc.
    private var tick = 0
    private let slowEvery = 5

    private let log = DiagnosticLog("sampler")
    private var sleepObservers: [NSObjectProtocol] = []

    private init() {
        start()
        observeSleepAndWake()
    }

    /// Somn: oprim ceasul (zero treziri în timp ce Mac-ul doarme). Trezire:
    /// contorii vechi sunt aruncați și primul ciclu doar stabilește o bază,
    /// altfel un delta peste ore de somn ar arăta un vârf inventat.
    private func observeSleepAndWake() {
        let center = NSWorkspace.shared.notificationCenter
        sleepObservers.append(center.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleSleep() }
        })
        sleepObservers.append(center.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleWake() }
        })
    }

    func handleSleep() {
        log.info("Somn: eșantionarea oprită")
        stop()
    }

    func handleWake() {
        log.info("Trezire: baze reinițializate, eșantionarea repornește")
        cpuMonitor.resetBaseline()
        networkMonitor.resetBaseline()
        processMonitor.resetBaseline()
        start()
    }

    var isRunning: Bool { timer != nil }

    // MARK: - Ciclul

    func start() {
        guard timer == nil else { return }
        // `.common` ca să nu înghețe graficele cât timp utilizatorul ține
        // apăsat un meniu sau redimensionează fereastra.
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.collect() }
        }
        // 10% toleranță: sistemul poate grupa trezirea cu altele (Regula 21).
        timer.tolerance = interval * 0.1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        collect()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func restart() {
        stop()
        start()
    }

    private func collect() {
        cpu = cpuMonitor.sample()
        memory = memoryMonitor.sample()
        network = networkMonitor.sample()
        processes = processMonitor.sample(sortedBy: processSort)

        cpuHistory.append(cpu.total)
        memoryHistory.append(memory.usedFraction)
        downloadHistory.append(network.downloadRate)
        uploadHistory.append(network.uploadRate)

        if tick % slowEvery == 0 {
            disks = diskMonitor.sample()
            battery = batteryMonitor.sample()
        }
        tick &+= 1
    }
}

/// Un inel de valori de dimensiune fixă. Plafonul e parte din tip, nu o
/// convenție pe care cineva trebuie să și-o amintească.
struct History {
    private(set) var values: [Double] = []
    let capacity: Int

    init(capacity: Int) {
        self.capacity = capacity
        values.reserveCapacity(capacity)
    }

    mutating func append(_ value: Double) {
        values.append(value)
        if values.count > capacity {
            values.removeFirst(values.count - capacity)
        }
    }

    var maximum: Double { values.max() ?? 0 }
    var latest: Double { values.last ?? 0 }
    var isEmpty: Bool { values.isEmpty }
}
