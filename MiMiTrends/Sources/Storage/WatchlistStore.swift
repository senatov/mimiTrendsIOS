import Foundation
import SQLite3

struct WatchlistEntry: Codable, Identifiable, Equatable, Sendable {
    let symbol: String
    let addedAtMillis: Int64

    var id: String { symbol }

    enum CodingKeys: String, CodingKey {
        case symbol
        case addedAtMillis = "added_at"
    }
}

actor WatchlistStore {
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
            throw WatchlistStoreError.databaseUnavailable
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
        ).appendingPathComponent("mimitrends-watchlist.db")
    }

    func load() throws -> [WatchlistEntry] {
        let statement = try prepare("SELECT symbol, added_at FROM user_watchlist ORDER BY added_at, symbol")
        defer { sqlite3_finalize(statement) }
        var entries: [WatchlistEntry] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { return entries }
            guard result == SQLITE_ROW,
                  let rawSymbol = sqlite3_column_text(statement, 0) else {
                throw WatchlistStoreError.databaseUnavailable
            }
            entries.append(WatchlistEntry(
                symbol: String(cString: rawSymbol),
                addedAtMillis: sqlite3_column_int64(statement, 1)
            ))
        }
    }

    @discardableResult
    func add(_ symbol: String, atMillis: Int64 = Int64(Date().timeIntervalSince1970 * 1_000)) throws -> Bool {
        let normalized = try Self.normalize(symbol)
        let statement = try prepare("INSERT OR IGNORE INTO user_watchlist(symbol, added_at) VALUES (?, ?)")
        defer { sqlite3_finalize(statement) }
        try bind(normalized, to: 1, in: statement)
        sqlite3_bind_int64(statement, 2, atMillis)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw WatchlistStoreError.databaseUnavailable
        }
        return sqlite3_changes(database) > 0
    }

    func remove(_ symbol: String) throws {
        let normalized = try Self.normalize(symbol)
        let statement = try prepare("DELETE FROM user_watchlist WHERE symbol = ?")
        defer { sqlite3_finalize(statement) }
        try bind(normalized, to: 1, in: statement)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw WatchlistStoreError.databaseUnavailable
        }
    }

    static func normalize(_ symbol: String) throws -> String {
        let value = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.:-_")
        guard !value.isEmpty, value.utf8.count <= 32,
              value.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            throw WatchlistStoreError.invalidSymbol
        }
        return value
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else { throw WatchlistStoreError.databaseUnavailable }
        return statement
    }

    private func bind(_ value: String, to index: Int32, in statement: OpaquePointer) throws {
        guard sqlite3_bind_text(statement, index, value, -1, Self.transient) == SQLITE_OK else {
            throw WatchlistStoreError.databaseUnavailable
        }
    }

    private static func migrate(_ connection: OpaquePointer) throws {
        try execute("""
            CREATE TABLE IF NOT EXISTS native_schema_migrations(
                version INTEGER PRIMARY KEY, applied_at INTEGER NOT NULL)
            """, on: connection)
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(connection,
            "SELECT COALESCE(MAX(version), 0) FROM native_schema_migrations", -1,
            &statement, nil) == SQLITE_OK, let statement else {
            throw WatchlistStoreError.databaseUnavailable
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw WatchlistStoreError.databaseUnavailable
        }
        let version = sqlite3_column_int(statement, 0)
        guard version <= 1 else { throw WatchlistStoreError.unsupportedSchema }
        if version == 1 { return }

        try execute("BEGIN IMMEDIATE", on: connection)
        do {
            try execute("""
                CREATE TABLE user_watchlist(
                    symbol TEXT PRIMARY KEY,
                    added_at INTEGER NOT NULL)
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
              let statement else { throw WatchlistStoreError.databaseUnavailable }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW,
              String(cString: sqlite3_column_text(statement, 0)) == "ok" else {
            throw WatchlistStoreError.integrityCheckFailed
        }
    }

    private static func execute(_ sql: String, on connection: OpaquePointer) throws {
        guard sqlite3_exec(connection, sql, nil, nil, nil) == SQLITE_OK else {
            throw WatchlistStoreError.databaseUnavailable
        }
    }
}

enum WatchlistStoreError: LocalizedError {
    case databaseUnavailable
    case invalidSymbol
    case unsupportedSchema
    case integrityCheckFailed

    var errorDescription: String? {
        switch self {
        case .databaseUnavailable: "Watchlist storage is unavailable."
        case .invalidSymbol: "Enter a symbol using letters, numbers, dots, dashes, underscores, or colons."
        case .unsupportedSchema: "This watchlist database was created by a newer app version."
        case .integrityCheckFailed: "Watchlist database integrity check failed."
        }
    }
}
