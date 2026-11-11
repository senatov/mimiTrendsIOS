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
        let other = try await reopened.candidateSnapshot(source: "boerseDAX")
        XCTAssertTrue(other.isEmpty)
    }
}
