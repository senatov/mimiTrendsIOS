import Foundation
import XCTest
@testable import MiMiTrends

final class AppDiagnosticsTests: XCTestCase {
    func testWritesTimestampedDiagnosticEventsToRequestedFile() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("diagnostics-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appendingPathComponent("events.log")
        let diagnostics = AppDiagnostics(preferredURL: url)
        diagnostics.record(.warning, "Charts", "load-complete", "symbol=ORCL bars=0")

        XCTAssertEqual(diagnostics.fileURL(), url)
        let contents = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(contents.contains("WARN [Charts] load-complete symbol=ORCL bars=0"))
    }

    func testRotatesFileAtConfiguredSize() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("diagnostics-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appendingPathComponent("events.log")
        let diagnostics = AppDiagnostics(preferredURL: url, maximumBytes: 110)
        diagnostics.record(.info, "Test", "first", String(repeating: "a", count: 60))
        diagnostics.record(.info, "Test", "second", String(repeating: "b", count: 60))
        _ = diagnostics.fileURL()

        let current = try String(contentsOf: url, encoding: .utf8)
        let previous = try String(contentsOf: directory.appendingPathComponent("events.previous.log"),
                                  encoding: .utf8)
        XCTAssertTrue(previous.contains("[Test] first"))
        XCTAssertTrue(current.contains("[Test] second"))
    }
}
