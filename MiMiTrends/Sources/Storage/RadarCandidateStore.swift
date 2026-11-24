import Foundation
import CryptoKit

/// Candidate discovery is independent of the frequently updated minute-bar database.
actor RadarCandidateStore {
    private struct Snapshot: Codable {
        let source: String
        let savedAt: Date
        let candidates: [RadarCompanyCandidate]
    }

    private struct EIXSnapshot: Codable {
        let savedAt: Date
        let isins: Set<String>
    }

    private let directory: URL
    private var lastPrunedAt: Date = .distantPast

    init(directory: URL) {
        self.directory = directory
    }

    static func defaultDirectory() throws -> URL {
        try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                    appropriateFor: nil, create: true)
            .appendingPathComponent("mimitrends-radar-candidates", isDirectory: true)
    }

    func candidateSnapshot(source: String) throws -> [RadarCompanyCandidate] {
        let url = try fileURL(source: source)
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let snapshot = try JSONDecoder().decode(Snapshot.self, from: Data(contentsOf: url))
        guard snapshot.source == source, Date().timeIntervalSince(snapshot.savedAt) < 86_400 else { return [] }
        return snapshot.candidates
    }

    func saveCandidateSnapshot(_ candidates: [RadarCompanyCandidate], source: String) throws {
        guard !candidates.isEmpty else { return }
        let url = try fileURL(source: source)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(Snapshot(source: source, savedAt: Date(), candidates: candidates))
            .write(to: url, options: .atomic)
    }

    func eixSnapshot() throws -> Set<String> {
        let url = try fileURL(source: "eix-instruments")
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let snapshot = try JSONDecoder().decode(EIXSnapshot.self, from: Data(contentsOf: url))
        guard Date().timeIntervalSince(snapshot.savedAt) < 48 * 3_600,
              snapshot.isins.count >= EIXInstrumentSource.minimumDistinctISINs else { return [] }
        return snapshot.isins
    }

    func saveEIXSnapshot(_ isins: Set<String>) throws {
        guard !isins.isEmpty else { return }
        let url = try fileURL(source: "eix-instruments")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(EIXSnapshot(savedAt: Date(), isins: isins))
            .write(to: url, options: .atomic)
    }

    func pruneExpiredSnapshots(now: Date = Date()) throws -> Int {
        guard now.timeIntervalSince(lastPrunedAt) >= 3_600 else { return 0 }
        guard FileManager.default.fileExists(atPath: directory.path) else {
            lastPrunedAt = now
            return 0
        }
        let urls = try FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        )
        let eixURL = try fileURL(source: "eix-instruments")
        var removed = 0
        for url in urls where url.pathExtension == "json" && url.lastPathComponent.count == 69 {
            let valid: Bool
            if url == eixURL {
                valid = (try? JSONDecoder().decode(EIXSnapshot.self, from: Data(contentsOf: url)))
                    .map { $0.savedAt <= now && now.timeIntervalSince($0.savedAt) < 48 * 3_600 &&
                        $0.isins.count >= EIXInstrumentSource.minimumDistinctISINs } ?? false
            } else {
                valid = (try? JSONDecoder().decode(Snapshot.self, from: Data(contentsOf: url)))
                    .map { $0.savedAt <= now && now.timeIntervalSince($0.savedAt) < 86_400 && !$0.candidates.isEmpty } ?? false
            }
            if !valid {
                try FileManager.default.removeItem(at: url)
                removed += 1
            }
        }
        lastPrunedAt = now
        return removed
    }

    private func fileURL(source: String) throws -> URL {
        guard source.utf8.count <= 4_096, !source.isEmpty else { throw CocoaError(.fileReadInvalidFileName) }
        let encoded = SHA256.hash(data: Data(source.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(encoded + ".json")
    }
}
