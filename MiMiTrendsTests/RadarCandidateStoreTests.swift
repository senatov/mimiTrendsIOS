import Foundation
import XCTest
@testable import MiMiTrends

final class RadarCandidateStoreTests: XCTestCase {
    func testSnapshotsRemainIndependentOfBarDatabase() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = RadarCandidateStore(directory: directory)
        let candidates = [RadarCompanyCandidate(symbol: "AAPL", name: "Apple")]
        let source = "baseline|" + String(repeating: "https://example.org/ranking/", count: 12) + "|US"
        try await store.saveCandidateSnapshot(candidates, source: source)
        let reopened = RadarCandidateStore(directory: directory)
        let loaded = try await reopened.candidateSnapshot(source: source)
        XCTAssertEqual(loaded.map(\.symbol), ["AAPL"])
        let other = try await reopened.candidateSnapshot(source: "tradingViewDE")
        XCTAssertTrue(other.isEmpty)
    }

    func testHourlyCleanupRemovesOnlyExpiredCandidateSnapshots() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = RadarCandidateStore(directory: directory)
        try await store.saveCandidateSnapshot([RadarCompanyCandidate(symbol: "OLD", name: "Old")], source: "old")
        try await store.saveCandidateSnapshot([RadarCompanyCandidate(symbol: "NEW", name: "New")], source: "new")
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        for file in files {
            var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
            if (json["candidates"] as? [[String: Any]])?.first?["symbol"] as? String == "OLD" {
                json["savedAt"] = Date(timeIntervalSinceNow: -90_000).timeIntervalSinceReferenceDate
                try JSONSerialization.data(withJSONObject: json).write(to: file)
            }
        }
        let removed = try await store.pruneExpiredSnapshots()
        let old = try await store.candidateSnapshot(source: "old")
        let new = try await store.candidateSnapshot(source: "new")
        let secondPass = try await store.pruneExpiredSnapshots()
        XCTAssertEqual(removed, 1)
        XCTAssertTrue(old.isEmpty)
        XCTAssertEqual(new.map(\.symbol), ["NEW"])
        XCTAssertEqual(secondPass, 0)
    }
}
