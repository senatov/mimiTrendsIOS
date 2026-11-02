// LogKit.swift
// LogKit
//
// Created by Iakov Senatov on 23.02.2026.
// Copyright © 2026 Senatov. All rights reserved.
// Description: Shared logging module for MiMiNavigator and all sub-packages.
//   Wraps SwiftyBeaver. Import LogKit anywhere → use log.debug / log.info / log.error.
//   Initialization (destinations, file path) is done once in the main app via LogKit.initialize().
//   Sub-packages only need `import LogKit` — they never call initialize() themselves.

import Foundation


// MARK: - LogKit
public enum LogKit {
    public struct RotationPolicy {
        public var maxFileSizeBytes: UInt64
        public var uncompressedBackupCount: Int
        public var maximumBackupCount: Int

        public init(
            maxFileSizeBytes: UInt64 = 50 * 1024 * 1024,
            uncompressedBackupCount: Int = 3,
            maximumBackupCount: Int = 6
        ) {
            self.maxFileSizeBytes = maxFileSizeBytes
            self.uncompressedBackupCount = uncompressedBackupCount
            self.maximumBackupCount = maximumBackupCount
        }
    }

    // MARK: - Call once from AppDelegate / @main before any log.xxx() call
    public static func initialize(
        appSupportSubdir: String = "MiMiNavigator",
        logFileName: String = "MiMiNavigator.log",
        wipeOnLaunch: Bool = false,
        rotationPolicy: RotationPolicy = .init()
    ) {
        setupConsole()
        setupFile(
            appSupportSubdir: appSupportSubdir,
            logFileName: logFileName,
            wipeOnLaunch: wipeOnLaunch,
            rotationPolicy: rotationPolicy)
        setupTmpFile(
            logFileName: logFileName,
            wipeOnLaunch: wipeOnLaunch,
            rotationPolicy: rotationPolicy
        )
    }

    // MARK: - Console destination
    private static func setupConsole() {
        let console = ConsoleDestination()
        console.useTerminalColors = true
        console.useNSLog = false
        console.format = "$DHH:mm:ss$d $L $N.$F:$l $M"
        console.levelString.verbose = "􀐯 VERBOSE"
        console.levelString.debug = "􀌚 DEBUG"
        console.levelString.info = "􀅴 INFO"
        console.levelString.warning = "⚠️ WARNING"
        console.levelString.error = "❗️ ERROR"
        console.levelString.critical = "🔥 CRITICAL"
        console.levelString.fault = "💥 FAULT"
        log.addDestination(console)
    }

    // MARK: - File destination
    private static func setupFile(
        appSupportSubdir: String,
        logFileName: String,
        wipeOnLaunch: Bool,
        rotationPolicy: RotationPolicy
    ) {
        guard
            let base = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return }

        let logsDir =
            base
            .appendingPathComponent(appSupportSubdir, isDirectory: true)
            .appendingPathComponent("Logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
        let logFile = logsDir.appendingPathComponent(logFileName)
        if wipeOnLaunch {
            archiveExistingLog(at: logFile)
        }
        let file = RotatingFileDestination(
            logFileURL: logFile,
            maxFileSizeBytes: rotationPolicy.maxFileSizeBytes,
            uncompressedBackupCount: rotationPolicy.uncompressedBackupCount,
            maximumBackupCount: rotationPolicy.maximumBackupCount
        )
        file.asynchronously = false
        log.addDestination(file)
        log.info("[LogKit] logging to: \(logFile.path)")
    }

    // MARK: - /tmp file destination (always accessible, outside sandbox)
    private static func setupTmpFile(
        logFileName: String,
        wipeOnLaunch: Bool,
        rotationPolicy: RotationPolicy
    ) {
        let tmpLog = URL(fileURLWithPath: "/tmp/\(logFileName)")
        if wipeOnLaunch {
            archiveExistingLog(at: tmpLog)
        }
        let file = RotatingFileDestination(
            logFileURL: tmpLog,
            maxFileSizeBytes: rotationPolicy.maxFileSizeBytes,
            uncompressedBackupCount: rotationPolicy.uncompressedBackupCount,
            maximumBackupCount: rotationPolicy.maximumBackupCount
        )
        file.asynchronously = false
        file.format = "$DHH:mm:ss.SSS$d $L $N.$F():$l - $M"
        log.addDestination(file)
        log.info("[LogKit] also logging to: \(tmpLog.path)")
    }

    // MARK: - Preserve Previous Session Log
    private static func archiveExistingLog(at logURL: URL) {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: logURL.path),
              let attributes = try? fileManager.attributesOfItem(atPath: logURL.path),
              (attributes[.size] as? NSNumber)?.uint64Value ?? 0 > 0
        else { return }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        let stem = logURL.deletingPathExtension().lastPathComponent
        let archiveName = "\(stem).previous-\(formatter.string(from: Date())).log"
        let archiveURL = logURL.deletingLastPathComponent().appendingPathComponent(archiveName)
        do {
            try fileManager.moveItem(at: logURL, to: archiveURL)
            trimPreviousSessionLogs(beside: logURL, stem: stem, keeping: 10)
            log.info("[LogKit] preserved previous session log: \(archiveURL.path)")
        } catch {
            log.warning("[LogKit] failed to preserve previous session log '\(logURL.path)': \(error.localizedDescription)")
        }
    }

    // MARK: - Trim Previous Session Logs
    private static func trimPreviousSessionLogs(beside logURL: URL, stem: String, keeping limit: Int) {
        let directory = logURL.deletingLastPathComponent()
        let prefix = "\(stem).previous-"
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        let archives = entries.filter { $0.lastPathComponent.hasPrefix(prefix) && $0.pathExtension == "log" }
            .sorted { lhs, rhs in
                let leftDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let rightDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return leftDate > rightDate
            }
        for expired in archives.dropFirst(limit) {
            try? FileManager.default.removeItem(at: expired)
        }
    }

    public static func flush(timeoutSeconds: TimeInterval = 2) {
        _ = log.flush(secondTimeout: Int64(timeoutSeconds.rounded(.up)))
    }

    // MARK: - Log file URL (for settings/bug reports)
    public static func logFileURL(
        appSupportSubdir: String = "MiMiNavigator",
        logFileName: String = "MiMiNavigator.log"
    ) -> URL? {
        guard
            let base = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return nil }
        return
            base
            .appendingPathComponent(appSupportSubdir, isDirectory: true)
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent(logFileName)
    }
}
