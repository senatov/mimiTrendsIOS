import Foundation
import SQLite3

actor MarketSignalStore {
    private let database: OpaquePointer

    init(url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        var connection: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(url.path, &connection, flags, nil) == SQLITE_OK,
              let connection else {
            if let connection { sqlite3_close(connection) }
            throw MarketSignalStoreError.databaseUnavailable
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

    isolated deinit {
        sqlite3_close(database)
    }

    static func defaultURL() throws -> URL {
        try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        ).appendingPathComponent("mimitrends-signals.db")
    }

    func record(_ signal: ScanResult) throws -> Bool {
        let symbol = signal.symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !symbol.isEmpty, !signal.signalSource.isEmpty, signal.signalEpochMillis > 0 else {
            throw MarketSignalStoreError.invalidSignal
        }
        let payload = try JSONEncoder().encode(signal)
        let statement = try prepare("""
            INSERT OR IGNORE INTO signals(symbol, source, signal_epoch, evaluated_at, payload)
            VALUES (?, ?, ?, ?, ?)
            """)
        defer { sqlite3_finalize(statement) }
        try bind(symbol, to: 1, in: statement)
        let sourceKey = signal.dataStatus == YahooCandleSignalPipeline.volumeValidatedStatus ||
              signal.dataStatus == YahooCandleSignalPipeline.delayedVolumeValidatedStatus
                ? "\(signal.signalSource)|YAHOO_VOLUME_VALIDATED" : signal.signalSource
        try bind(sourceKey, to: 2, in: statement)
        sqlite3_bind_int64(statement, 3, signal.signalEpochMillis)
        sqlite3_bind_int64(statement, 4, signal.scanEvaluatedAtMillis)
        let result = payload.withUnsafeBytes { bytes in
            sqlite3_bind_blob(statement, 5, bytes.baseAddress, Int32(bytes.count), Self.transient)
        }
        guard result == SQLITE_OK, sqlite3_step(statement) == SQLITE_DONE else {
            throw MarketSignalStoreError.databaseUnavailable
        }
        return sqlite3_changes(database) > 0
    }

    func loadRecent(limit: Int = 100, sinceEpochMillis: Int64 = 0) throws -> [ScanResult] {
        let statement = try prepare("""
            SELECT payload FROM signals
            WHERE signal_epoch >= ?
            ORDER BY signal_epoch DESC, symbol, source LIMIT ?
            """)
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, max(sinceEpochMillis, 0))
        sqlite3_bind_int(statement, 2, Int32(min(max(limit, 1), 500)))
        var signals: [ScanResult] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { return signals }
            guard result == SQLITE_ROW,
                  let bytes = sqlite3_column_blob(statement, 0) else {
                throw MarketSignalStoreError.databaseUnavailable
            }
            let data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 0)))
            signals.append(try JSONDecoder().decode(ScanResult.self, from: data))
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else { throw MarketSignalStoreError.databaseUnavailable }
        return statement
    }

    private func bind(_ text: String, to index: Int32, in statement: OpaquePointer) throws {
        guard sqlite3_bind_text(statement, index, text, -1, Self.transient) == SQLITE_OK else {
            throw MarketSignalStoreError.databaseUnavailable
        }
    }

    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private static func migrate(_ connection: OpaquePointer) throws {
        try execute("""
            CREATE TABLE IF NOT EXISTS native_schema_migrations(
                version INTEGER PRIMARY KEY, applied_at INTEGER NOT NULL)
            """, on: connection)
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(connection,
            "SELECT COALESCE(MAX(version), 0) FROM native_schema_migrations", -1,
            &statement, nil) == SQLITE_OK, let statement else {
            throw MarketSignalStoreError.databaseUnavailable
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw MarketSignalStoreError.databaseUnavailable
        }
        let version = sqlite3_column_int(statement, 0)
        guard version <= 1 else { throw MarketSignalStoreError.unsupportedSchema }
        if version == 1 { return }

        try execute("BEGIN IMMEDIATE", on: connection)
        do {
            try execute("""
                CREATE TABLE signals(
                    symbol TEXT NOT NULL, source TEXT NOT NULL,
                    signal_epoch INTEGER NOT NULL, evaluated_at INTEGER NOT NULL,
                    payload BLOB NOT NULL,
                    PRIMARY KEY(symbol, source, signal_epoch))
                """, on: connection)
            try execute("""
                INSERT INTO native_schema_migrations(version, applied_at)
                VALUES (1, \(Int64(Date().timeIntervalSince1970 * 1_000)))
                """, on: connection)
            try execute("COMMIT", on: connection)
        } catch {
            try? execute("ROLLBACK", on: connection)
            throw error
        }
    }

    private static func checkIntegrity(_ connection: OpaquePointer) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(connection, "PRAGMA quick_check", -1, &statement, nil) == SQLITE_OK,
              let statement else { throw MarketSignalStoreError.databaseUnavailable }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW,
              String(cString: sqlite3_column_text(statement, 0)) == "ok" else {
            throw MarketSignalStoreError.integrityCheckFailed
        }
    }

    private static func execute(_ sql: String, on connection: OpaquePointer) throws {
        guard sqlite3_exec(connection, sql, nil, nil, nil) == SQLITE_OK else {
            throw MarketSignalStoreError.databaseUnavailable
        }
    }
}

enum MarketSignalStoreError: LocalizedError {
    case databaseUnavailable
    case invalidSignal
    case unsupportedSchema
    case integrityCheckFailed

    var errorDescription: String? {
        switch self {
        case .databaseUnavailable: "Signal storage is unavailable."
        case .invalidSignal: "The detected signal is invalid."
        case .unsupportedSchema: "This signal database was created by a newer app version."
        case .integrityCheckFailed: "Signal database integrity check failed."
        }
    }
}
