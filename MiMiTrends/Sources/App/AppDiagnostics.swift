import Foundation
import os
#if os(macOS)
import Darwin
#endif

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
    private let maximumBytes: Int

    init(preferredURL: URL? = nil, maximumBytes: Int = 4 * 1_024 * 1_024) {
        self.maximumBytes = maximumBytes
        #if os(macOS)
        self.preferredURL = preferredURL ?? Self.macOSUserHomeDirectory()
            .appendingPathComponent("mimiTrendsiOS.log")
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
            if let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? NSNumber,
               size.intValue + bytes.count > maximumBytes {
                let previous = url.deletingPathExtension().appendingPathExtension("previous.log")
                try? FileManager.default.removeItem(at: previous)
                try FileManager.default.moveItem(at: url, to: previous)
                try Self.createEmptyLog(at: url)
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
        #if os(macOS)
        let containerLog = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("mimiTrendsiOS.log")
        #endif
        let fallback = FileManager.default.temporaryDirectory.appendingPathComponent("mimiTrendsiOS.log")
        #if os(macOS)
        let candidates = [preferredURL, containerLog, fallback]
        #else
        let candidates = [preferredURL, fallback]
        #endif
        for candidate in candidates {
            do {
                if !FileManager.default.fileExists(atPath: candidate.path) {
                    try Self.createEmptyLog(at: candidate)
                }
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: candidate.path)
                activeURL = candidate
                if candidate != preferredURL {
                    console.warning("Preferred log unavailable; using \(candidate.path, privacy: .public)")
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

    private static func createEmptyLog(at url: URL) throws {
        guard FileManager.default.createFile(atPath: url.path, contents: Data(),
                                             attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown)
        }
    }

    #if os(macOS)
    private static func macOSUserHomeDirectory() -> URL {
        guard let user = getpwuid(getuid()), let path = user.pointee.pw_dir else {
            return FileManager.default.homeDirectoryForCurrentUser
        }
        return URL(fileURLWithPath: String(cString: path), isDirectory: true)
    }
    #endif
}
