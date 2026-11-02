import Foundation
import SQLite3

actor BrokerTransactionStore {
    private let database: OpaquePointer
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        var connection: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(url.path, &connection, flags, nil) == SQLITE_OK,
              let connection else {
            if let connection { sqlite3_close(connection) }
            throw BrokerTransactionStoreError.databaseUnavailable
        }
        do {
            try Self.execute("PRAGMA journal_mode=WAL", on: connection)
            try Self.execute("PRAGMA busy_timeout=10000", on: connection)
            try Self.migrate(connection)
            try Self.checkIntegrity(connection)
        } catch {
            sqlite3_close(connection)
            throw error
        }
        database = connection
    }

    isolated deinit { sqlite3_close(database) }

    static func defaultURL() throws -> URL {
        try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        ).appendingPathComponent("mimitrends-broker-trades.db")
    }

    func importTransactions(_ transactions: [BrokerTransaction]) throws -> BrokerImportWriteResult {
        guard transactions.count <= 100_000 else { throw BrokerTransactionStoreError.invalidBatch }
        let statement = try prepare("""
            INSERT OR IGNORE INTO broker_transactions(
                source, reference, fingerprint, occurred_at, status, description,
                asset_type, type, isin, shares, price, amount, fee, tax, currency, imported_at
            ) VALUES ('SCALABLE', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """)
        defer { sqlite3_finalize(statement) }
        try Self.execute("BEGIN IMMEDIATE", on: database)
        do {
            var imported = 0
            var importedByType: [String: Int] = [:]
            for transaction in transactions {
                sqlite3_reset(statement)
                sqlite3_clear_bindings(statement)
                try bind(transaction.reference, to: 1, in: statement)
                try bind(transaction.fingerprint, to: 2, in: statement)
                sqlite3_bind_int64(statement, 3, transaction.occurredAtEpochSeconds)
                try bind(transaction.status, to: 4, in: statement)
                try bind(transaction.description, to: 5, in: statement)
                try bind(transaction.assetType, to: 6, in: statement)
                try bind(transaction.type, to: 7, in: statement)
                try bind(transaction.isin, to: 8, in: statement)
                sqlite3_bind_double(statement, 9, transaction.shares)
                sqlite3_bind_double(statement, 10, transaction.price)
                sqlite3_bind_double(statement, 11, transaction.amount)
                sqlite3_bind_double(statement, 12, transaction.fee)
                sqlite3_bind_double(statement, 13, transaction.tax)
                try bind(transaction.currency, to: 14, in: statement)
                sqlite3_bind_int64(statement, 15, Int64(Date().timeIntervalSince1970))
                guard sqlite3_step(statement) == SQLITE_DONE else {
                    throw BrokerTransactionStoreError.databaseUnavailable
                }
                if sqlite3_changes(database) > 0 {
                    imported += 1
                    let kind = transaction.type.isEmpty ? "Other" : transaction.type
                    importedByType[kind, default: 0] += 1
                }
            }
            try Self.execute("COMMIT", on: database)
            return BrokerImportWriteResult(
                importedCount: imported,
                duplicatesInDatabase: transactions.count - imported,
                importedByType: importedByType
            )
        } catch {
            try? Self.execute("ROLLBACK", on: database)
            throw error
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else { throw BrokerTransactionStoreError.databaseUnavailable }
        return statement
    }

    private func bind(_ value: String?, to index: Int32, in statement: OpaquePointer) throws {
        let result: Int32
        if let value {
            result = sqlite3_bind_text(statement, index, value, -1, Self.transient)
        } else {
            result = sqlite3_bind_null(statement, index)
        }
        guard result == SQLITE_OK else { throw BrokerTransactionStoreError.databaseUnavailable }
    }

    private static func migrate(_ connection: OpaquePointer) throws {
        try execute("""
            CREATE TABLE IF NOT EXISTS broker_transactions(
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                source TEXT NOT NULL,
                reference TEXT,
                fingerprint TEXT NOT NULL UNIQUE,
                occurred_at INTEGER NOT NULL,
                status TEXT NOT NULL,
                description TEXT NOT NULL,
                asset_type TEXT NOT NULL,
                type TEXT NOT NULL,
                isin TEXT,
                shares REAL NOT NULL,
                price REAL NOT NULL,
                amount REAL NOT NULL,
                fee REAL NOT NULL,
                tax REAL NOT NULL,
                currency TEXT NOT NULL,
                imported_at INTEGER NOT NULL
            )
            """, on: connection)
        try execute("""
            CREATE UNIQUE INDEX IF NOT EXISTS idx_broker_source_reference
            ON broker_transactions(source, reference) WHERE reference IS NOT NULL
            """, on: connection)
        try execute("""
            CREATE TABLE IF NOT EXISTS native_schema_migrations(
                version INTEGER PRIMARY KEY, applied_at INTEGER NOT NULL)
            """, on: connection)
        try execute("""
            INSERT OR IGNORE INTO native_schema_migrations(version, applied_at)
            VALUES (1, \(Int64(Date().timeIntervalSince1970 * 1_000)))
            """, on: connection)
    }

    private static func checkIntegrity(_ connection: OpaquePointer) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(connection, "PRAGMA quick_check", -1, &statement, nil) == SQLITE_OK,
              let statement else { throw BrokerTransactionStoreError.databaseUnavailable }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW,
              String(cString: sqlite3_column_text(statement, 0)) == "ok" else {
            throw BrokerTransactionStoreError.integrityCheckFailed
        }
    }

    private static func execute(_ sql: String, on connection: OpaquePointer) throws {
        guard sqlite3_exec(connection, sql, nil, nil, nil) == SQLITE_OK else {
            throw BrokerTransactionStoreError.databaseUnavailable
        }
    }
}

enum BrokerTransactionStoreError: LocalizedError {
    case databaseUnavailable, integrityCheckFailed, invalidBatch

    var errorDescription: String? {
        switch self {
        case .databaseUnavailable: "Could not save imported trades."
        case .integrityCheckFailed: "The local trade database failed its integrity check."
        case .invalidBatch: "The trade import is too large."
        }
    }
}
