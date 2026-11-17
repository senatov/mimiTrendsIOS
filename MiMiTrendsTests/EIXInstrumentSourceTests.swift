import XCTest
@testable import MiMiTrends

final class EIXInstrumentSourceTests: XCTestCase {
    func testOpeningFileUsesFirstSnapshotOnNewestDay() {
        let keys = [
            "pretrade/2026-11-16/Pretrade.1794866700000.csv.gz",
            "pretrade/2026-11-17/Pretrade.1794891900000.csv.gz",
            "pretrade/2026-11-17/Pretrade.1794891600000.csv.gz"
        ]
        XCTAssertEqual(EIXInstrumentSource.openingFile(in: keys), keys[2])
    }

    func testPretradeISINsAndCandidateReplacement() {
        let csv = Data("Trading day & Trading time UTC,Instrument Identifier,Bid Quantity\n2026-11-17T06:00:00Z,US0378331005,100\n2026-11-17T06:00:00Z,DE0007164600,100\n".utf8)
        let available = EIXInstrumentSource.parseISINs(csv)
        let candidates = [
            RadarCompanyCandidate(symbol: "ERAS", name: "Erasca", isin: "US29479A1088"),
            RadarCompanyCandidate(symbol: "AAPL", name: "Apple", isin: "US0378331005"),
            RadarCompanyCandidate(symbol: "UNKNOWN", name: "Unknown"),
            RadarCompanyCandidate(symbol: "SAP.DE", name: "SAP", isin: "DE0007164600")
        ]
        let eligible = MarketRadarScanner.eixCandidates(candidates, availableISINs: available)
        XCTAssertEqual(eligible.map(\.symbol), ["AAPL", "SAP.DE"])
        XCTAssertFalse(available.contains("US29479A1088"))
    }
}
