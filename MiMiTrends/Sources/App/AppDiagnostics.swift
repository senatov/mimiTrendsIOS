import Foundation
import os

final class AppDiagnostics: @unchecked Sendable {
    static let shared = AppDiagnostics()

    enum Level: String {
        case info = "INFO"
        case warning = "WARN"
        case error = "ERROR"
    }

    private let queue = DispatchQueue(label: "org.senatov.mimitrends.diagnostics", qos: .utility)
    private let console = Logger(subsystem: "org.senatov.mimitrends.apple", category: "Diagnostics")
    private let preferredURL: URL
    private var activeURL: URL?
    private let maximumBytes = 4 * 1_024 * 1_024

    init(preferredURL: URL? = nil) {
        #if os(macOS)
        self.preferredURL = preferredURL ?? URL(fileURLWithPath: "/tmp/mimiTrendsiOS.log")
        #else
        self.preferredURL = preferredURL ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("mimiTrendsiOS.log")
        #endif
    }

    func record(_ level: Level = .info, _ component: String, _ event: String, _ details: String = "") {
        let line = "\(Self.timestamp()) \(level.rawValue) [\(component)] \(event)\(details.isEmpty ? "" : " \(details)")"
        switch level {
        case .info: console.info("\(line, privacy: .public)")
        case .warning: console.warning("\(line, privacy: .public)")
        case .error: console.error("\(line, privacy: .public)")
        }
        queue.async { [self] in append(line) }
    }

    func fileURL() -> URL? {
        queue.sync { activeURL ?? prepareFile() }
    }

    private func append(_ line: String) {
        guard let url = activeURL ?? prepareFile(), let bytes = (line + "\n").data(using: .utf8) else { return }
        do {
            if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
               size + bytes.count > maximumBytes {
                let previous = url.deletingPathExtension().appendingPathExtension("previous.log")
                try? FileManager.default.removeItem(at: previous)
                try FileManager.default.moveItem(at: url, to: previous)
                try Data().write(to: url, options: .atomic)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            }
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: bytes)
        } catch {
            console.error("File log write failed: \(String(describing: type(of: error)), privacy: .public)")
        }
    }

    private func prepareFile() -> URL? {
        let fallback = FileManager.default.temporaryDirectory.appendingPathComponent("mimiTrendsiOS.log")
        for candidate in [preferredURL, fallback] {
            do {
                if !FileManager.default.fileExists(atPath: candidate.path) {
                    try Data().write(to: candidate, options: .atomic)
                }
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: candidate.path)
                activeURL = candidate
                if candidate != preferredURL {
                    console.warning("/tmp log unavailable; using \(candidate.path, privacy: .public)")
                }
                return candidate
            } catch { continue }
        }
        console.error("No writable diagnostics file in temporary storage")
        return nil
    }

    private static func timestamp() -> String {
        Date.now.ISO8601Format()
    }
}
