import Foundation
import XCTest
@testable import MiMiTrends

final class ScalableCSVImporterTests: XCTestCase {
    func testParsesGermanNumbersAndReportsCancelledAndDuplicateRows() throws {
        let header = "date;time;status;reference;description;assetType;type;isin;shares;price;amount;fee;tax;currency"
        let quoted = "2026-08-03;21:22:05;Executed;buy-220;\"SoFi; Tech \"\"Class A\"\"\";Security;Buy;US83406F1021;220;15,546;-3.420,12;0,00;0,00;EUR"
        let duplicate = "2026-08-03;21:22:05;Executed;buy-220;Duplicate;Security;Buy;US83406F1021;220;15,546;-3.420,12;0,00;0,00;EUR"
        let cancelled = "2026-08-03;21:43:14;Cancelled;sell-220;SoFi Technologies;Security;Sell;US83406F1021;220;15,508;3.411,76;0,99;-6,53;EUR"
        let data = Data([header, quoted, duplicate, cancelled].joined(separator: "\n").utf8)

        let result = try ScalableCSVImporter.parse(data)

        XCTAssertEqual(result.inputRows, 3)
        XCTAssertEqual(result.cancelledRows, 1)
        XCTAssertEqual(result.duplicatesInFile, 1)
        XCTAssertEqual(result.transactions.count, 1)
        XCTAssertEqual(result.transactions[0].description, "SoFi; Tech \"Class A\"")
        XCTAssertEqual(result.transactions[0].price, 15.546, accuracy: 0.000_001)
        XCTAssertEqual(result.transactions[0].amount, -3420.12, accuracy: 0.001)
        XCTAssertEqual(result.transactions[0].currency, "EUR")
    }

    func testRejectsMalformedRowsAndMissingColumns() throws {
        let missingHeader = Data("date;time\n2026-01-01;12:00:00".utf8)
        XCTAssertThrowsError(try ScalableCSVImporter.parse(missingHeader)) { error in
            XCTAssertEqual(error as? ScalableCSVError, .missingHeaders)
        }

        let invalidNumber = csvRow(price: "not-a-price")
        XCTAssertThrowsError(try ScalableCSVImporter.parse(Data(invalidNumber.utf8))) { error in
            XCTAssertEqual(error as? ScalableCSVError, .invalidNumber(row: 2, field: "price"))
        }
    }

    private func csvRow(price: String) -> String {
        """
        date;time;status;reference;description;assetType;type;isin;shares;price;amount;fee;tax;currency
        2026-08-03;21:22:05;Executed;buy-220;SoFi;Security;Buy;US83406F1021;220;\(price);-3.420,12;0,00;0,00;EUR
        """
    }
}

final class BrokerTransactionStoreTests: XCTestCase {
    func testImportIsTransactionalAndSkipsPreviouslyImportedTrades() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mimitrends-broker-test-\(UUID().uuidString)")
            .appendingPathComponent("trades.db")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = try BrokerTransactionStore(url: url)
        let first = try ScalableCSVImporter.parse(Data(Self.sampleCSV.utf8)).transactions
        let initial = try await store.importTransactions(first)
        let repeated = try await store.importTransactions(first)

        XCTAssertEqual(initial.importedCount, 1)
        XCTAssertEqual(initial.duplicatesInDatabase, 0)
        XCTAssertEqual(initial.importedByType["Buy"], 1)
        XCTAssertEqual(repeated.importedCount, 0)
        XCTAssertEqual(repeated.duplicatesInDatabase, 1)
        XCTAssertTrue(repeated.importedByType.isEmpty)
    }

    private static let sampleCSV = """
        date;time;status;reference;description;assetType;type;isin;shares;price;amount;fee;tax;currency
        2026-08-03;21:22:05;Executed;buy-220;SoFi Technologies;Security;Buy;US83406F1021;220;15,546;-3.420,12;0,00;0,00;EUR
        """
}
