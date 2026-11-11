import Foundation
import SQLite3

actor MarketBarStore {
    private let database: OpaquePointer
    static let retentionSeconds: Int64 = 30 * 60
    private let retentionEnabled: Bool
    private var lastPrunedAt: Date = .distantPast

    init(url: URL, retentionEnabled: Bool = true) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        var connection: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(url.path, &connection, flags, nil) == SQLITE_OK,
              let connection else {
            if let connection { sqlite3_close(connection) }
            throw MarketBarStoreError.databaseUnavailable
        }
        do {
            try Self.configure(connection)
            try Self.migrate(connection)
        } catch {
            AppDiagnostics.shared.record(
                .error, "MarketBarStore", "open-failed",
                "error=\(String(describing: type(of: error))) sqlite=\(String(cString: sqlite3_errmsg(connection)))"
            )
            sqlite3_close(connection)
            throw error
        }
        database = connection
        self.retentionEnabled = retentionEnabled
    }

    isolated deinit {
        sqlite3_close(database)
    }

    static func finnhubURL() throws -> URL {
        try defaultURL().deletingLastPathComponent().appendingPathComponent("mimitrends-finnhub-bars.db")
    }

    static func defaultURL() throws -> URL {
        try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        ).appendingPathComponent("mimitrends-native.db")
    }

    func upsert(_ bar: MinuteBar) throws -> Bool {
        guard bar.isValid else { throw MarketBarStoreError.invalidBar }
        if retentionEnabled {
            let now = Date()
            try pruneIfNeeded(now: now)
            guard bar.minuteEpochSeconds >= Int64(now.timeIntervalSince1970) - Self.retentionSeconds else { return false }
        }
        let sql = """
            INSERT INTO minute_bars(symbol, minute_epoch, open, high, low, close, volume,
                volume_status, source_currency, currency_status)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'INFERRED')
            ON CONFLICT(symbol, minute_epoch) DO UPDATE SET
                open=excluded.open, high=excluded.high, low=excluded.low,
                close=excluded.close, volume=excluded.volume, volume_status=excluded.volume_status,
                source_currency=excluded.source_currency, currency_status=excluded.currency_status
            WHERE minute_bars.open IS NOT excluded.open OR minute_bars.high IS NOT excluded.high
                OR minute_bars.low IS NOT excluded.low OR minute_bars.close IS NOT excluded.close
                OR minute_bars.volume IS NOT excluded.volume
                OR minute_bars.volume_status IS NOT excluded.volume_status
                OR minute_bars.source_currency IS NOT excluded.source_currency
                OR minute_bars.currency_status IS NOT excluded.currency_status
            """
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        let symbol = bar.symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !symbol.isEmpty else { throw MarketBarStoreError.invalidBar }
        try bind(symbol, to: 1, in: statement)
        sqlite3_bind_int64(statement, 2, bar.minuteEpochSeconds)
        sqlite3_bind_double(statement, 3, bar.open)
        sqlite3_bind_double(statement, 4, bar.high)
        sqlite3_bind_double(statement, 5, bar.low)
        sqlite3_bind_double(statement, 6, bar.close)
        sqlite3_bind_double(statement, 7, bar.volume)
        try bind(bar.volumeStatus.rawValue, to: 8, in: statement)
        try bind(Self.currency(for: symbol), to: 9, in: statement)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw MarketBarStoreError.databaseUnavailable }
        return sqlite3_changes(database) > 0
    }

    func upsertBatch(_ bars: [MinuteBar]) throws -> Int {
        guard bars.count <= 360, bars.allSatisfy(\.isValid) else {
            throw MarketBarStoreError.invalidBar
        }
        if retentionEnabled { try pruneIfNeeded(now: Date()) }
        try Self.execute("BEGIN IMMEDIATE", on: database)
        do {
            var changed = 0
            for bar in bars {
                if try upsert(bar) { changed += 1 }
            }
            try Self.execute("COMMIT", on: database)
            return changed
        } catch {
            try? Self.execute("ROLLBACK", on: database)
            throw error
        }
    }

    func loadMinuteBars(symbol: String, fromEpochSeconds: Int64, limit: Int = 10_000) throws -> [MinuteBar] {
        let sql = """
            SELECT minute_epoch, open, high, low, close, volume, volume_status FROM minute_bars
            WHERE symbol=? AND minute_epoch>=? ORDER BY minute_epoch LIMIT ?
            """
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        let normalized = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        try bind(normalized, to: 1, in: statement)
        sqlite3_bind_int64(statement, 2, retentionCutoff(from: fromEpochSeconds))
        sqlite3_bind_int(statement, 3, Int32(min(max(limit, 1), 10_000)))
        var bars: [MinuteBar] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { return bars }
            guard result == SQLITE_ROW else { throw MarketBarStoreError.databaseUnavailable }
            let statusName = String(cString: sqlite3_column_text(statement, 6))
            bars.append(MinuteBar(
                symbol: normalized,
                minuteEpochSeconds: sqlite3_column_int64(statement, 0),
                open: sqlite3_column_double(statement, 1),
                high: sqlite3_column_double(statement, 2),
                low: sqlite3_column_double(statement, 3),
                close: sqlite3_column_double(statement, 4),
                volume: sqlite3_column_double(statement, 5),
                volumeStatus: VolumeStatus(rawValue: statusName) ?? .missing
            ))
        }
    }

    func loadRecentMinuteBars(
        symbol: String, fromEpochSeconds: Int64, throughEpochSeconds: Int64, limit: Int = 360
    ) throws -> [MinuteBar] {
        let sql = """
            SELECT minute_epoch, open, high, low, close, volume, volume_status FROM minute_bars
            WHERE symbol=? AND minute_epoch>=? AND minute_epoch<=?
            ORDER BY minute_epoch DESC LIMIT ?
            """
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        let normalized = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        try bind(normalized, to: 1, in: statement)
        sqlite3_bind_int64(statement, 2, retentionCutoff(from: fromEpochSeconds))
        sqlite3_bind_int64(statement, 3, throughEpochSeconds)
        sqlite3_bind_int(statement, 4, Int32(min(max(limit, 1), 2_000)))
        var bars: [MinuteBar] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { return bars.reversed() }
            guard result == SQLITE_ROW else { throw MarketBarStoreError.databaseUnavailable }
            let statusName = String(cString: sqlite3_column_text(statement, 6))
            bars.append(MinuteBar(
                symbol: normalized,
                minuteEpochSeconds: sqlite3_column_int64(statement, 0),
                open: sqlite3_column_double(statement, 1),
                high: sqlite3_column_double(statement, 2),
                low: sqlite3_column_double(statement, 3),
                close: sqlite3_column_double(statement, 4),
                volume: sqlite3_column_double(statement, 5),
                volumeStatus: VolumeStatus(rawValue: statusName) ?? .missing
            ))
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            AppDiagnostics.shared.record(
                .error, "MarketBarStore", "prepare-failed",
                "sqlite=\(String(cString: sqlite3_errmsg(database)))"
            )
            throw MarketBarStoreError.databaseUnavailable
        }
        return statement
    }

    private func bind(_ text: String, to index: Int32, in statement: OpaquePointer) throws {
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        guard sqlite3_bind_text(statement, index, text, -1, transient) == SQLITE_OK else {
            throw MarketBarStoreError.databaseUnavailable
        }
    }

    private static func configure(_ connection: OpaquePointer) throws {
        try execute("PRAGMA busy_timeout=10000", on: connection)
        try execute("PRAGMA journal_mode=WAL", on: connection)
        try execute("PRAGMA foreign_keys=ON", on: connection)
    }

    private static func migrate(_ connection: OpaquePointer) throws {
        try execute(
            "CREATE TABLE IF NOT EXISTS native_schema_migrations(version INTEGER PRIMARY KEY, applied_at INTEGER NOT NULL)",
            on: connection
        )
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(connection, "SELECT COALESCE(MAX(version), 0) FROM native_schema_migrations", -1, &statement, nil) == SQLITE_OK,
              let statement else { throw MarketBarStoreError.databaseUnavailable }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { throw MarketBarStoreError.databaseUnavailable }
        let version = sqlite3_column_int(statement, 0)
        guard version <= 1 else { throw MarketBarStoreError.unsupportedSchema }
        if version == 1 { return }

        try execute("BEGIN IMMEDIATE", on: connection)
        do {
            try execute("""
                CREATE TABLE minute_bars (
                    symbol TEXT NOT NULL, minute_epoch INTEGER NOT NULL,
                    open REAL NOT NULL, high REAL NOT NULL, low REAL NOT NULL,
                    close REAL NOT NULL, volume REAL NOT NULL,
                    volume_status TEXT NOT NULL DEFAULT 'MISSING',
                    source_currency TEXT, currency_status TEXT,
                    PRIMARY KEY(symbol, minute_epoch)
                )
                """, on: connection)
            let appliedAt = Int64(Date().timeIntervalSince1970 * 1_000)
            try execute(
                "INSERT INTO native_schema_migrations(version, applied_at) VALUES (1, \(appliedAt))",
                on: connection
            )
            try execute("COMMIT", on: connection)
        } catch {
            try? execute("ROLLBACK", on: connection)
            throw error
        }
    }

    private func retentionCutoff(from requested: Int64) -> Int64 {
        guard retentionEnabled else { return requested }
        return max(requested, Int64(Date().timeIntervalSince1970) - Self.retentionSeconds)
    }

    private func pruneIfNeeded(now: Date) throws {
        guard retentionEnabled, now.timeIntervalSince(lastPrunedAt) >= 60 else { return }
        try Self.pruneOldBars(on: database, now: now)
        lastPrunedAt = now
    }

    private static func pruneOldBars(on connection: OpaquePointer, now: Date) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(connection, "DELETE FROM minute_bars WHERE minute_epoch < ?",
                                 -1, &statement, nil) == SQLITE_OK, let statement else {
            throw MarketBarStoreError.databaseUnavailable
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, Int64(now.timeIntervalSince1970) - retentionSeconds)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw MarketBarStoreError.databaseUnavailable }
    }

    private static func execute(_ sql: String, on connection: OpaquePointer) throws {
        guard sqlite3_exec(connection, sql, nil, nil, nil) == SQLITE_OK else {
            throw MarketBarStoreError.databaseUnavailable
        }
    }

    private static func currency(for symbol: String) -> String {
        [".DE", ".F", ".PA", ".AS", ".MI", ".HE"].contains(where: symbol.hasSuffix) ? "EUR" : "USD"
    }
}

enum MarketBarStoreError: LocalizedError {
    case databaseUnavailable
    case invalidBar
    case unsupportedSchema
    case integrityCheckFailed

    var errorDescription: String? {
        switch self {
        case .databaseUnavailable: "Market data storage is unavailable."
        case .invalidBar: "The received market bar is invalid."
        case .unsupportedSchema: "This market database was created by a newer app version."
        case .integrityCheckFailed: "Market database integrity check failed."
        }
    }
}
