import Foundation

/// Scoate din text ce nu are ce căuta într-un log sau într-un pachet de
/// suport: calea directorului personal, adrese de email, șiruri lungi care
/// seamănă a token (OBSERVABILITY_STANDARD, «Confidențialitate»).
enum DiagnosticRedactor {
    static func redact(_ text: String, home: String = NSHomeDirectory()) -> String {
        var result = text
        if home.count > 1 {
            result = result.replacingOccurrences(of: home, with: "~")
        }
        // /Users/<nume>/… rămas din alte conturi sau din căi nenormalizate.
        result = result.replacingRegex(#"/Users/[^/\s]+"#, with: "/Users/<user>")
        result = result.replacingRegex(#"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#, with: "<email>")
        // Chei/tokenuri: 32+ caractere hex sau base64url consecutive.
        result = result.replacingRegex(#"\b[A-Za-z0-9_\-]{32,}\b"#, with: "<redacted>")
        return result
    }
}

private extension String {
    func replacingRegex(_ pattern: String, with template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return self }
        let range = NSRange(startIndex..., in: self)
        return regex.stringByReplacingMatches(in: self, range: range, withTemplate: template)
    }
}

/// „Exportă diagnosticul”: un ZIP local, inspectabil, cu logurile redactate
/// și un manifest. Nu se încarcă nicăieri; utilizatorul decide dacă îl trimite.
enum DiagnosticExporter {
    enum ExportError: Error { case zipFailed(Int32) }

    /// Manifest fără date personale. `settings` conține doar chei tehnice.
    static func manifest(settings: [String: String]) -> [String: Any] {
        let info = ProcessInfo.processInfo
        return [
            "app": "Farul",
            "bundleID": DiagnosticLog.subsystem,
            "version": DiagnosticLog.appVersion,
            "sessionID": DiagnosticLog.sessionID,
            "platform": "macOS \(info.operatingSystemVersionString)",
            "architecture": architecture(),
            "createdAt": ISO8601DateFormatter().string(from: Date()),
            "settings": settings,
            "contents": ["Farul.log", "Farul.log.1", "manifest.json"],
            "note": "Pachet local. Nu a fost trimis nicăieri. Căile și emailurile sunt redactate.",
        ]
    }

    static func architecture() -> String {
        var size = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        var buffer = [CChar](repeating: 0, count: max(size, 1))
        sysctlbyname("hw.machine", &buffer, &size, nil, 0)
        return String(cString: buffer)
    }

    /// Scrie `destination` (un `.zip`). Returnează destinația.
    @discardableResult
    static func export(to destination: URL, settings: [String: String],
                       logDirectory: URL = DiagnosticLog.directory) throws -> URL {
        let fm = FileManager.default
        let stage = fm.temporaryDirectory.appendingPathComponent("farul-diag-\(UUID().uuidString)", isDirectory: true)
        let folder = stage.appendingPathComponent("Farul-diagnostic", isDirectory: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: stage) }

        for name in ["Farul.log", "Farul.log.1"] {
            let source = logDirectory.appendingPathComponent(name)
            guard let data = try? Data(contentsOf: source), let text = String(data: data, encoding: .utf8) else { continue }
            try DiagnosticRedactor.redact(text).write(to: folder.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        let json = try JSONSerialization.data(withJSONObject: manifest(settings: settings), options: [.prettyPrinted, .sortedKeys])
        try json.write(to: folder.appendingPathComponent("manifest.json"))

        try? fm.removeItem(at: destination)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--keepParent", folder.path, destination.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw ExportError.zipFailed(process.terminationStatus) }
        return destination
    }
}
