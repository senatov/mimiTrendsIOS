#if os(macOS)
import AppKit
import Darwin
import Foundation

@MainActor
enum LocalAccountInstanceGuard {
    private static let instance = InstanceLock()

    static func activateExistingInstanceOrExit() {
        guard instance.isSecondaryLaunch else { return }
        for _ in 0..<100 {
            if let process = instance.runningOwner,
               process.bundleIdentifier == Bundle.main.bundleIdentifier {
                process.activate(options: [.activateAllWindows])
                AppDiagnostics.shared.record(.info, "App", "duplicate-launch-activated", "pid=\(process.processIdentifier)")
                Darwin.exit(EXIT_SUCCESS)
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        Darwin.exit(EXIT_FAILURE)
    }
}

private final class InstanceLock {
    private let lockURL: URL
    private let descriptor: Int32
    private let ownsLock: Bool

    var isSecondaryLaunch: Bool { !ownsLock }

    var runningOwner: NSRunningApplication? {
        guard let ownerPID = Self.readOwnerPID(from: lockURL) else { return nil }
        return NSRunningApplication(processIdentifier: ownerPID)
    }

    init() {
        let supportDirectory = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        )[0].appendingPathComponent(AppIdentity.name, isDirectory: true)
        do {
            try FileManager.default.createDirectory(
                at: supportDirectory, withIntermediateDirectories: true
            )
        } catch {
            fatalError("Unable to prepare the per-user application lock.")
        }

        let lockURL = supportDirectory.appendingPathComponent("single-instance.lock")
        self.lockURL = lockURL
        let openedDescriptor = open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard openedDescriptor >= 0 else {
            fatalError("Unable to open the per-user application lock.")
        }
        descriptor = openedDescriptor

        if flock(descriptor, LOCK_EX | LOCK_NB) == 0 {
            ownsLock = true
            writeOwnerPID()
        } else {
            ownsLock = false
            close(descriptor)
        }
    }

    private func writeOwnerPID() {
        let bytes = Array(String(getpid()).utf8)
        _ = ftruncate(descriptor, 0)
        _ = lseek(descriptor, 0, SEEK_SET)
        bytes.withUnsafeBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            _ = write(descriptor, baseAddress, buffer.count)
        }
    }

    private static func readOwnerPID(from url: URL) -> pid_t? {
        guard let value = try? String(contentsOf: url, encoding: .utf8),
              let pid = pid_t(value.trimmingCharacters(in: .whitespacesAndNewlines)),
              pid > 0 else { return nil }
        return pid
    }
}
#endif
