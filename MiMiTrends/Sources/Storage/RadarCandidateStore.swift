import Foundation
import CryptoKit

/// Candidate discovery is independent of the frequently updated minute-bar database.
actor RadarCandidateStore {
    private struct Snapshot: Codable {
        let source: String
        let savedAt: Date
        let candidates: [RadarCompanyCandidate]
    }

    private let directory: URL

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

    private func fileURL(source: String) throws -> URL {
        guard source.utf8.count <= 4_096, !source.isEmpty else { throw CocoaError(.fileReadInvalidFileName) }
        let encoded = SHA256.hash(data: Data(source.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(encoded + ".json")
    }
}
