import Foundation
import SQLite3

actor RadarCompanyMetadataStore {
    private let database: OpaquePointer

    init(url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var connection: OpaquePointer?
        guard sqlite3_open_v2(url.path, &connection,
                              SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX,
                              nil) == SQLITE_OK, let connection else {
            if let connection { sqlite3_close(connection) }
            throw RadarCompanyMetadataStoreError.unavailable
        }
        let sql = """
            CREATE TABLE IF NOT EXISTS company_metadata (
              symbol TEXT PRIMARY KEY NOT NULL, name TEXT NOT NULL,
              country_code TEXT, logo BLOB, updated_at INTEGER NOT NULL
            )
            """
        guard sqlite3_exec(connection, "PRAGMA busy_timeout=5000", nil, nil, nil) == SQLITE_OK,
              sqlite3_exec(connection, sql, nil, nil, nil) == SQLITE_OK else {
            sqlite3_close(connection)
            throw RadarCompanyMetadataStoreError.unavailable
        }
        database = connection
    }

    isolated deinit { sqlite3_close(database) }

    static func defaultURL() throws -> URL {
        try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                    appropriateFor: nil, create: true)
            .appendingPathComponent("mimitrends-company-metadata.db")
    }

    func load(symbols: [String]) throws -> [String: RadarCompanyMetadata] {
        guard !symbols.isEmpty else { return [:] }
        var result: [String: RadarCompanyMetadata] = [:]
        let statement = try prepare("SELECT symbol, name, country_code, logo, updated_at FROM company_metadata WHERE symbol = ?")
        defer { sqlite3_finalize(statement) }
        for symbol in symbols {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
            bind(symbol, at: 1, in: statement)
            guard sqlite3_step(statement) == SQLITE_ROW,
                  let symbolValue = text(statement, column: 0),
                  let name = text(statement, column: 1) else { continue }
            let country = text(statement, column: 2)
            let logo = sqlite3_column_blob(statement, 3).map { Data(bytes: $0, count: Int(sqlite3_column_bytes(statement, 3))) }
            result[symbolValue] = RadarCompanyMetadata(
                symbol: symbolValue, name: name, countryCode: country,
                logoData: logo, updatedAtMillis: sqlite3_column_int64(statement, 4)
            )
        }
        return result
    }

    func save(_ metadata: RadarCompanyMetadata) throws {
        let statement = try prepare("""
            INSERT INTO company_metadata(symbol, name, country_code, logo, updated_at)
            VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(symbol) DO UPDATE SET name=excluded.name, country_code=excluded.country_code,
              logo=COALESCE(excluded.logo, company_metadata.logo), updated_at=excluded.updated_at
            """)
        defer { sqlite3_finalize(statement) }
        bind(metadata.symbol, at: 1, in: statement)
        bind(metadata.name, at: 2, in: statement)
        bind(metadata.countryCode, at: 3, in: statement)
        if let logo = metadata.logoData {
            _ = logo.withUnsafeBytes { sqlite3_bind_blob(statement, 4, $0.baseAddress, Int32($0.count), Self.transient) }
        } else { sqlite3_bind_null(statement, 4) }
        sqlite3_bind_int64(statement, 5, metadata.updatedAtMillis)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw RadarCompanyMetadataStoreError.unavailable }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw RadarCompanyMetadataStoreError.unavailable
        }
        return statement
    }

    private func bind(_ value: String?, at index: Int32, in statement: OpaquePointer) {
        guard let value else { sqlite3_bind_null(statement, index); return }
        sqlite3_bind_text(statement, index, value, -1, Self.transient)
    }

    private func text(_ statement: OpaquePointer, column: Int32) -> String? {
        guard let value = sqlite3_column_text(statement, column) else { return nil }
        return String(cString: value)
    }

    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
}

enum RadarCompanyMetadataStoreError: Error { case unavailable }
