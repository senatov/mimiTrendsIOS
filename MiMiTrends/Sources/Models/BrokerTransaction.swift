import Foundation

struct BrokerTransaction: Sendable, Equatable {
    let reference: String?
    let fingerprint: String
    let occurredAtEpochSeconds: Int64
    let status: String
    let description: String
    let assetType: String
    let type: String
    let isin: String?
    let shares: Double
    let price: Double
    let amount: Double
    let fee: Double
    let tax: Double
    let currency: String
}

struct BrokerTradeExecution: Sendable, Equatable {
    let id: Int64
    let occurredAtEpochSeconds: Int64
    let description: String
    let type: String
    let isin: String?
    let shares: Double
    let price: Double
    let amount: Double
    let fee: Double
    let tax: Double
    let currency: String
}

struct BrokerTradePosition: Identifiable, Sendable, Equatable {
    let id: String
    let symbol: String
    let quantity: Double
    let entryEpochSeconds: Int64
    let entryPrice: Double
    let exitEpochSeconds: Int64?
    let exitPrice: Double?
    let profitAmount: Double?
    let profitPercent: Double?
    let currency: String
}

struct ScalableCSVParseResult: Sendable {
    let inputRows: Int
    let cancelledRows: Int
    let duplicatesInFile: Int
    let transactions: [BrokerTransaction]
}

struct BrokerImportWriteResult: Sendable {
    let importedCount: Int
    let duplicatesInDatabase: Int
    let importedByType: [String: Int]
}

struct BrokerImportReport: Identifiable, Sendable {
    let id = UUID()
    let fileName: String
    let inputRows: Int
    let cancelledRows: Int
    let duplicatesInFile: Int
    let transactionsInFile: Int
    let importedCount: Int
    let duplicatesInDatabase: Int
    let importedByType: [String: Int]

    var duplicateCount: Int { duplicatesInFile + duplicatesInDatabase }
    var ignoredCount: Int { cancelledRows + duplicateCount }
}
