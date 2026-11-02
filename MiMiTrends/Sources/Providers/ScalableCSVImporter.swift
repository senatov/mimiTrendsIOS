import CryptoKit
import Foundation

enum ScalableCSVImporter {
    private static let maximumFileSize = 50_000_000
    private static let maximumRows = 100_000
    private static let requiredHeaders: Set<String> = [
        "date", "time", "status", "reference", "description", "assetType", "type",
        "isin", "shares", "price", "amount", "fee", "tax", "currency"
    ]

    static func read(url: URL) async throws -> ScalableCSVParseResult {
        try await Task.detached(priority: .userInitiated) {
            let hasScopedAccess = url.startAccessingSecurityScopedResource()
            defer {
                if hasScopedAccess { url.stopAccessingSecurityScopedResource() }
            }
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size > 0, size <= maximumFileSize else { throw ScalableCSVError.fileTooLarge }
            return try parse(Data(contentsOf: url))
        }.value
    }

    static func parse(_ data: Data) throws -> ScalableCSVParseResult {
        guard data.count > 0, data.count <= maximumFileSize else {
            throw ScalableCSVError.fileTooLarge
        }
        guard let contents = String(data: data, encoding: .utf8) else {
            throw ScalableCSVError.invalidEncoding
        }
        var lines = contents.components(separatedBy: .newlines).filter {
            !$0.trimmingCharacters(in: .whitespaces).isEmpty
        }
        guard let headerLine = lines.first else { throw ScalableCSVError.emptyFile }
        lines.removeFirst()
        let headers = try parseLine(headerLine).map {
            $0.replacingOccurrences(of: "\u{FEFF}", with: "").trimmingCharacters(in: .whitespaces)
        }
        let headerSet = Set(headers)
        guard headerSet.count == headers.count, headerSet.isSuperset(of: requiredHeaders) else {
            throw ScalableCSVError.missingHeaders
        }
        guard lines.count <= maximumRows else { throw ScalableCSVError.tooManyRows }
        let positions = Dictionary(uniqueKeysWithValues: headers.enumerated().map { ($1, $0) })
        let dateFormatter = makeDateFormatter()
        var cancelled = 0
        var transactions: [BrokerTransaction] = []
        var seen = Set<String>()
        var duplicates = 0

        for (index, line) in lines.enumerated() {
            let rowNumber = index + 2
            do {
                let values = try parseLine(line)
                func value(_ name: String) -> String {
                    guard let position = positions[name], values.indices.contains(position) else { return "" }
                    return values[position].trimmingCharacters(in: .whitespaces)
                }
                let status = value("status")
                if isCancelled(status) {
                    cancelled += 1
                    continue
                }
                let canonical = headers.map { value($0) }.joined(separator: "\u{1F}")
                guard let date = dateFormatter.date(from: "\(value("date")) \(value("time"))") else {
                    throw ScalableCSVError.invalidDate(row: rowNumber)
                }
                let reference = value("reference").nilIfBlank
                let fingerprint = fingerprint(canonical)
                let deduplicationKey = reference.map { "reference:\($0)" } ?? "fingerprint:\(fingerprint)"
                guard seen.insert(deduplicationKey).inserted else {
                    duplicates += 1
                    continue
                }
                transactions.append(BrokerTransaction(
                    reference: reference,
                    fingerprint: fingerprint,
                    occurredAtEpochSeconds: Int64(date.timeIntervalSince1970),
                    status: canonicalText(status),
                    description: value("description"),
                    assetType: canonicalText(value("assetType")),
                    type: canonicalText(value("type")),
                    isin: value("isin").uppercased().nilIfBlank,
                    shares: try number(value("shares"), row: rowNumber, field: "shares", nonNegative: true),
                    price: try number(value("price"), row: rowNumber, field: "price", nonNegative: true),
                    amount: try number(value("amount"), row: rowNumber, field: "amount"),
                    fee: try number(value("fee"), row: rowNumber, field: "fee", nonNegative: true),
                    tax: try number(value("tax"), row: rowNumber, field: "tax"),
                    currency: value("currency").uppercased()
                ))
            } catch let error as ScalableCSVError {
                throw error
            } catch {
                throw ScalableCSVError.invalidRow(row: rowNumber)
            }
        }
        return ScalableCSVParseResult(
            inputRows: lines.count, cancelledRows: cancelled,
            duplicatesInFile: duplicates, transactions: transactions
        )
    }

    private static func parseLine(_ line: String) throws -> [String] {
        var fields: [String] = []
        var field = ""
        var quoted = false
        var index = line.startIndex
        while index < line.endIndex {
            let character = line[index]
            let next = line.index(after: index)
            if character == "\"" {
                if quoted, next < line.endIndex, line[next] == "\"" {
                    field.append("\"")
                    index = next
                } else {
                    quoted.toggle()
                }
            } else if character == ";", !quoted {
                fields.append(field)
                field = ""
            } else {
                field.append(character)
            }
            index = line.index(after: index)
        }
        guard !quoted else { throw ScalableCSVError.unclosedQuote }
        fields.append(field)
        return fields
    }

    private static func makeDateFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "Europe/Berlin")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.isLenient = false
        return formatter
    }

    private static func number(
        _ text: String, row: Int, field: String, nonNegative: Bool = false
    ) throws -> Double {
        let normalized = text.replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: ",", with: ".")
        let parsed = normalized.isEmpty ? 0 : Double(normalized)
        guard let parsed, parsed.isFinite, !nonNegative || parsed >= 0 else {
            throw ScalableCSVError.invalidNumber(row: row, field: field)
        }
        return parsed
    }

    private static func fingerprint(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func canonicalText(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().capitalized
    }

    private static func isCancelled(_ status: String) -> Bool {
        ["cancelled", "cancel"].contains(status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }
}

private extension String {
    var nilIfBlank: String? { isEmpty ? nil : self }
}

enum ScalableCSVError: LocalizedError, Equatable {
    case fileTooLarge, invalidEncoding, emptyFile, missingHeaders, tooManyRows
    case unclosedQuote
    case invalidDate(row: Int)
    case invalidNumber(row: Int, field: String)
    case invalidRow(row: Int)

    var errorDescription: String? {
        switch self {
        case .fileTooLarge: "Choose a nonempty CSV file smaller than 50 MB."
        case .invalidEncoding: "The selected CSV file is not valid UTF-8."
        case .emptyFile: "The selected CSV file is empty."
        case .missingHeaders: "This is not a supported Scalable transactions CSV."
        case .tooManyRows: "The CSV contains more than 100,000 transaction rows."
        case .unclosedQuote: "A quoted field is incomplete."
        case .invalidDate(let row): "Invalid transaction date or time on CSV row \(row)."
        case .invalidNumber(let row, let field): "Invalid \(field) value on CSV row \(row)."
        case .invalidRow(let row): "Could not read CSV row \(row)."
        }
    }
}
