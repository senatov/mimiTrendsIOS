import Foundation
@_exported import SwiftyBeaver

/// Apache-like rotating file logger:
/// active log + `.1`/`.2`/`.3` plain files, then older rotations as `.N.gz`.
final class RotatingFileDestination: BaseDestination {
    let logFileURL: URL
    let maxFileSizeBytes: UInt64
    let uncompressedBackupCount: Int
    let maximumBackupCount: Int
    let fileManager = FileManager.default

    override var defaultHashValue: Int {
        logFileURL.path.hashValue ^ 0x5f37_59df
    }

    init(
        logFileURL: URL,
        maxFileSizeBytes: UInt64 = 50 * 1024 * 1024,
        uncompressedBackupCount: Int = 3,
        maximumBackupCount: Int = 6
    ) {
        self.logFileURL = logFileURL
        self.maxFileSizeBytes = maxFileSizeBytes
        self.uncompressedBackupCount = max(1, uncompressedBackupCount)
        self.maximumBackupCount = max(self.uncompressedBackupCount, maximumBackupCount)
        super.init()
        removeExcessBackups()
    }

    override func send(
        _ level: SwiftyBeaver.Level,
        msg: String,
        thread: String,
        file: String,
        function: String,
        line: Int,
        context: Any? = nil
    ) -> String? {
        let formatted = super
            .send(
                level,
                msg: msg,
                thread: thread,
                file: file,
                function: function,
                line: line,
                context: context
            )

        guard let formatted else { return nil }
        writeLineIfPossible(formatted + "\n")
        return formatted
    }

    private func writeLineIfPossible(_ line: String) {
        guard let data = line.data(using: .utf8) else { return }
        do {
            try ensureParentDirectoryExists()
            try rotateIfNeeded(incomingBytes: UInt64(data.count))
            if !fileManager.fileExists(atPath: logFileURL.path) {
                _ = fileManager.createFile(atPath: logFileURL.path, contents: nil)
            }
            let handle = try FileHandle(forWritingTo: logFileURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
            fputs("RotatingFileDestination write failed for \(logFileURL.path): \(error)\n", stderr)
        }
    }

    private func ensureParentDirectoryExists() throws {
        let dir = logFileURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: dir.path) {
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    private func rotateIfNeeded(incomingBytes: UInt64) throws {
        guard fileManager.fileExists(atPath: logFileURL.path) else { return }
        let attrs = try fileManager.attributesOfItem(atPath: logFileURL.path)
        let currentSize = attrs[.size] as? UInt64 ?? 0
        guard currentSize + incomingBytes > maxFileSizeBytes else { return }

        try archiveOldestUncompressedBackupIfNeeded()
        try shiftActiveBackups()
        try fileManager.moveItem(at: logFileURL, to: rotatedURL(index: 1))
        removeExcessBackups()
    }

    private func archiveOldestUncompressedBackupIfNeeded() throws {
        let oldestPlainURL = rotatedURL(index: uncompressedBackupCount)
        guard fileManager.fileExists(atPath: oldestPlainURL.path) else { return }

        let archiveIndex = nextArchiveIndex()
        let archivePlainURL = rotatedURL(index: archiveIndex)
        if fileManager.fileExists(atPath: archivePlainURL.path) {
            try fileManager.removeItem(at: archivePlainURL)
        }
        try fileManager.moveItem(at: oldestPlainURL, to: archivePlainURL)
        gzipFileIfPossible(at: archivePlainURL)
    }

    private func shiftActiveBackups() throws {
        guard uncompressedBackupCount > 1 else { return }
        for index in stride(from: uncompressedBackupCount - 1, through: 1, by: -1) {
            let source = rotatedURL(index: index)
            let target = rotatedURL(index: index + 1)
            guard fileManager.fileExists(atPath: source.path) else { continue }
            if fileManager.fileExists(atPath: target.path) {
                try fileManager.removeItem(at: target)
            }
            try fileManager.moveItem(at: source, to: target)
        }
    }

    private func nextArchiveIndex() -> Int {
        let directory = logFileURL.deletingLastPathComponent()
        let baseName = logFileURL.deletingPathExtension().lastPathComponent
        let ext = logFileURL.pathExtension

        guard let items = try? fileManager.contentsOfDirectory(atPath: directory.path) else {
            return uncompressedBackupCount + 1
        }

        let regexPattern: String =
            if ext.isEmpty {
                "^\(NSRegularExpression.escapedPattern(for: baseName))\\.(\\d+)(?:\\.gz)?$"
            } else {
                "^\(NSRegularExpression.escapedPattern(for: baseName))\\.(\\d+)\\.\(NSRegularExpression.escapedPattern(for: ext))(?:\\.gz)?$"
            }

        guard let regex = try? NSRegularExpression(pattern: regexPattern) else {
            return uncompressedBackupCount + 1
        }

        let highestIndex = items.reduce(uncompressedBackupCount) { currentMax, item in
            let range = NSRange(location: 0, length: item.utf16.count)
            guard
                let match = regex.firstMatch(in: item, range: range),
                match.numberOfRanges > 1,
                let captureRange = Range(match.range(at: 1), in: item),
                let index = Int(item[captureRange])
            else {
                return currentMax
            }
            return max(currentMax, index)
        }

        return highestIndex + 1
    }

    private func rotatedURL(index: Int) -> URL {
        let directory = logFileURL.deletingLastPathComponent()
        let baseName = logFileURL.deletingPathExtension().lastPathComponent
        let ext = logFileURL.pathExtension
        let fileName = ext.isEmpty ? "\(baseName).\(index)" : "\(baseName).\(index).\(ext)"
        return directory.appendingPathComponent(fileName, isDirectory: false)
    }

    private func removeExcessBackups() {
        guard
            let items = try? fileManager.contentsOfDirectory(
                at: logFileURL.deletingLastPathComponent(),
                includingPropertiesForKeys: nil
            )
        else { return }
        for item in items {
            guard let index = backupIndex(for: item.lastPathComponent) else { continue }
            let size = (try? item.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            let oversizedPlainBackup = item.pathExtension != "gz" && UInt64(size) > maxFileSizeBytes
            if index > maximumBackupCount || oversizedPlainBackup {
                try? fileManager.removeItem(at: item)
            }
        }
    }

    private func backupIndex(for fileName: String) -> Int? {
        let escapedName = NSRegularExpression.escapedPattern(for: logFileURL.lastPathComponent)
        guard
            let regex = try? NSRegularExpression(
                pattern: "^\(escapedName.replacingOccurrences(of: "\\.log", with: ""))\\.(\\d+)\\.log(?:\\.gz)?$")
        else {
            return nil
        }
        let range = NSRange(fileName.startIndex..<fileName.endIndex, in: fileName)
        guard let match = regex.firstMatch(in: fileName, range: range),
            let indexRange = Range(match.range(at: 1), in: fileName)
        else { return nil }
        return Int(fileName[indexRange])
    }

    private func gzipFileIfPossible(at url: URL) {
#if os(macOS)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/gzip")
        process.arguments = ["-f", url.path]
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            fputs("RotatingFileDestination gzip failed for \(url.path): \(error)\n", stderr)
        }
#endif
    }
}
