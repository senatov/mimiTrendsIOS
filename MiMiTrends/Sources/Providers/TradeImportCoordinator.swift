import Foundation

enum TradeImportCoordinator {
    static func importScalableCSV(at url: URL) async throws -> BrokerImportReport {
        let parsed = try await ScalableCSVImporter.read(url: url)
        let store = try BrokerTransactionStore(url: BrokerTransactionStore.defaultURL())
        let saved = try await store.importTransactions(parsed.transactions)
        return BrokerImportReport(
            fileName: url.lastPathComponent,
            inputRows: parsed.inputRows,
            cancelledRows: parsed.cancelledRows,
            duplicatesInFile: parsed.duplicatesInFile,
            transactionsInFile: parsed.transactions.count,
            importedCount: saved.importedCount,
            duplicatesInDatabase: saved.duplicatesInDatabase,
            importedByType: saved.importedByType
        )
    }
}
