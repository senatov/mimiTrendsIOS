import Foundation
import SQLite3

struct MarketQuoteRecord: Sendable {
    let provider: String
    let instrumentID: String
    let observedAtMillis: Int64
    let priceEUR: Double
    let bidEUR: Double?
    let askEUR: Double?
    let sourceCurrency: String
    let sourcePrice: Double
    let euroUSDRate: Double?
    let fxObservedAtMillis: Int64?

    init(_ quote: MarketPageQuote) {
        provider = "LANG_SCHWARZ"
        instrumentID = quote.identifier
        observedAtMillis = quote.observedAtMillis
        priceEUR = quote.midpointEUR
        bidEUR = quote.bidEUR
        askEUR = quote.askEUR
        sourceCurrency = quote.sourceCurrency
        sourcePrice = (quote.sourceBid + quote.sourceAsk) / 2
        euroUSDRate = quote.euroUSDRate
        fxObservedAtMillis = quote.fxObservedAtMillis
    }

    init(_ quote: WallstreetOnlineQuote) {
        provider = "WALLSTREET_ONLINE"
        instrumentID = quote.instrumentID
        observedAtMillis = quote.observedAtMillis
        priceEUR = quote.priceEUR
        bidEUR = nil
        askEUR = nil
        sourceCurrency = quote.sourceCurrency
        sourcePrice = quote.sourcePrice
        euroUSDRate = quote.euroUSDRate
        fxObservedAtMillis = quote.fxObservedAtMillis
    }

    var isValid: Bool {
        let divisor = euroUSDRate ?? 1
        return ["LANG_SCHWARZ", "WALLSTREET_ONLINE"].contains(provider) &&
            !instrumentID.isEmpty && instrumentID.utf8.count <= 256 && observedAtMillis > 0 &&
            priceEUR.isFinite && priceEUR > 0 && sourcePrice.isFinite && sourcePrice > 0 &&
            (sourceCurrency == "EUR" && euroUSDRate == nil && fxObservedAtMillis == nil ||
             sourceCurrency == "USD" && euroUSDRate.map { $0 > 0.5 && $0 < 2 } == true &&
                fxObservedAtMillis.map { abs($0 - observedAtMillis) <= 5 * 60_000 } == true) &&
            abs(priceEUR - sourcePrice / divisor) < 0.0001 &&
            (bidEUR == nil && askEUR == nil ||
             bidEUR.map { bid in bid.isFinite && bid > 0 &&
                 askEUR.map { $0.isFinite && $0 >= bid } == true } == true)
    }
}

actor MarketQuoteStore {
    private let database: OpaquePointer

    init(url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        var connection: OpaquePointer?
        guard sqlite3_open_v2(url.path, &connection,
                              SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX,
                              nil) == SQLITE_OK, let connection else {
            if let connection { sqlite3_close(connection) }
            throw MarketQuoteStoreError.databaseUnavailable
        }
        do {
            guard sqlite3_exec(connection, "PRAGMA journal_mode=WAL", nil, nil, nil) == SQLITE_OK,
                  sqlite3_exec(connection, "PRAGMA busy_timeout=5000", nil, nil, nil) == SQLITE_OK,
                  sqlite3_exec(connection, """
                    CREATE TABLE IF NOT EXISTS quote_observations (
                      provider TEXT NOT NULL, instrument_id TEXT NOT NULL,
                      observed_at INTEGER NOT NULL, price_eur REAL NOT NULL,
                      bid_eur REAL, ask_eur REAL, source_currency TEXT NOT NULL,
                      source_price REAL NOT NULL, eur_usd_rate REAL, fx_observed_at INTEGER,
                      PRIMARY KEY(provider, instrument_id, observed_at)
                    )
                    """, nil, nil, nil) == SQLITE_OK else {
                throw MarketQuoteStoreError.databaseUnavailable
            }
        } catch {
            sqlite3_close(connection)
            throw error
        }
        database = connection
    }

    isolated deinit { sqlite3_close(database) }

    static func defaultURL() throws -> URL {
        try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                    appropriateFor: nil, create: true)
            .appendingPathComponent("mimitrends-quotes.db")
    }

    func record(_ records: [MarketQuoteRecord], nowMillis: Int64) throws -> Int {
        guard records.count <= 300,
              records.allSatisfy({ $0.isValid && $0.observedAtMillis <= nowMillis + 30_000 &&
                  $0.observedAtMillis >= nowMillis - 600_000 }) else {
            throw MarketQuoteStoreError.invalidQuote
        }
        guard sqlite3_exec(database, "BEGIN IMMEDIATE", nil, nil, nil) == SQLITE_OK else {
            throw MarketQuoteStoreError.databaseUnavailable
        }
        do {
            let sql = """
                INSERT OR IGNORE INTO quote_observations
                (provider, instrument_id, observed_at, price_eur, bid_eur, ask_eur,
                 source_currency, source_price, eur_usd_rate, fx_observed_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
                  let statement else { throw MarketQuoteStoreError.databaseUnavailable }
            defer { sqlite3_finalize(statement) }
            var inserted = 0
            for record in records {
                sqlite3_reset(statement)
                sqlite3_clear_bindings(statement)
                try bind(record.provider, at: 1, in: statement)
                try bind(record.instrumentID, at: 2, in: statement)
                sqlite3_bind_int64(statement, 3, record.observedAtMillis)
                sqlite3_bind_double(statement, 4, record.priceEUR)
                bind(record.bidEUR, at: 5, in: statement)
                bind(record.askEUR, at: 6, in: statement)
                try bind(record.sourceCurrency, at: 7, in: statement)
                sqlite3_bind_double(statement, 8, record.sourcePrice)
                bind(record.euroUSDRate, at: 9, in: statement)
                if let fxAt = record.fxObservedAtMillis { sqlite3_bind_int64(statement, 10, fxAt) }
                else { sqlite3_bind_null(statement, 10) }
                guard sqlite3_step(statement) == SQLITE_DONE else {
                    throw MarketQuoteStoreError.databaseUnavailable
                }
                inserted += Int(sqlite3_changes(database))
            }
            let cutoff = nowMillis - 72 * 3_600_000
            var prune: OpaquePointer?
            guard sqlite3_prepare_v2(database, "DELETE FROM quote_observations WHERE observed_at < ?",
                                     -1, &prune, nil) == SQLITE_OK, let prune else {
                throw MarketQuoteStoreError.databaseUnavailable
            }
            sqlite3_bind_int64(prune, 1, cutoff)
            let pruned = sqlite3_step(prune) == SQLITE_DONE
            sqlite3_finalize(prune)
            guard pruned, sqlite3_exec(database, "COMMIT", nil, nil, nil) == SQLITE_OK else {
                throw MarketQuoteStoreError.databaseUnavailable
            }
            return inserted
        } catch {
            sqlite3_exec(database, "ROLLBACK", nil, nil, nil)
            throw error
        }
    }

    private func bind(_ value: String, at index: Int32, in statement: OpaquePointer) throws {
        guard sqlite3_bind_text(statement, index, value, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)) == SQLITE_OK else {
            throw MarketQuoteStoreError.databaseUnavailable
        }
    }

    private func bind(_ value: Double?, at index: Int32, in statement: OpaquePointer) {
        if let value { sqlite3_bind_double(statement, index, value) }
        else { sqlite3_bind_null(statement, index) }
    }
}

enum MarketQuoteStoreError: Error {
    case databaseUnavailable, invalidQuote
}
