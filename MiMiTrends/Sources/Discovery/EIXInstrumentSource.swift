import Foundation
import zlib

/// Uses the public opening pre-trade file as a conservative daily set of EIX ISINs.
struct EIXInstrumentSource: Sendable {
    private struct FileEntry: Decodable { let fileName: String }
    private let session: URLSession

    init(session: URLSession = .shared) { self.session = session }

    func load() async throws -> Set<String> {
        let root = URL(string: "https://european-investor-exchange.com")!
        let index = root.appending(path: "/api/trade-files")
        var indexParts = URLComponents(url: index, resolvingAgainstBaseURL: false)!
        indexParts.queryItems = [URLQueryItem(name: "tradeFileType", value: "pretrade")]
        let entries = try JSONDecoder().decode([FileEntry].self, from: try await data(indexParts.url!))
        guard let key = Self.openingFile(in: entries.map(\.fileName)) else {
            throw EIXSourceError.missingFile
        }
        var fileParts = URLComponents(url: root.appending(path: "/api/trade-file-contents"),
                                      resolvingAgainstBaseURL: false)!
        fileParts.queryItems = [URLQueryItem(name: "key", value: key),
                                URLQueryItem(name: "attachmentFilename", value: "Pretrade.csv.gz")]
        let compressed = try await data(fileParts.url!)
        let isins = try Self.parseGzip(compressed)
        guard isins.count >= 5_000 else { throw EIXSourceError.incompleteFile }
        return isins
    }

    private func data(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await BrowserPageRequest.send(request, using: session)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
            throw EIXSourceError.invalidResponse
        }
        return data
    }

    static func openingFile(in keys: [String]) -> String? {
        let valid = keys.compactMap { key -> (day: String, timestamp: Int64, key: String)? in
            let parts = key.split(separator: "/")
            guard parts.count == 3, parts[0] == "pretrade", parts[1].count == 10,
                  parts[2].hasPrefix("Pretrade."), parts[2].hasSuffix(".csv.gz"),
                  let timestamp = Int64(parts[2].dropFirst(9).dropLast(7)) else { return nil }
            return (String(parts[1]), timestamp, key)
        }
        guard let newestDay = valid.map(\.day).max() else { return nil }
        return valid.filter { $0.day == newestDay }.min { $0.timestamp < $1.timestamp }?.key
    }

    static func parseGzip(_ compressed: Data) throws -> Set<String> {
        guard compressed.count >= 2, compressed[0] == 0x1f, compressed[1] == 0x8b,
              compressed.count <= 15_000_000 else { throw EIXSourceError.invalidResponse }
        var stream = z_stream()
        guard inflateInit2_(&stream, 15 + 32, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
            throw EIXSourceError.invalidResponse
        }
        defer { inflateEnd(&stream) }
        var output = Data()
        let result = compressed.withUnsafeBytes { input -> Int32 in
            stream.next_in = UnsafeMutablePointer(mutating: input.bindMemory(to: Bytef.self).baseAddress!)
            stream.avail_in = uInt(compressed.count)
            var status: Int32 = Z_OK
            repeat {
                var chunk = [UInt8](repeating: 0, count: 65_536)
                status = chunk.withUnsafeMutableBytes { bytes in
                    stream.next_out = bytes.bindMemory(to: Bytef.self).baseAddress!
                    stream.avail_out = uInt(bytes.count)
                    let value = inflate(&stream, Z_NO_FLUSH)
                    output.append(contentsOf: bytes.prefix(bytes.count - Int(stream.avail_out)))
                    return value
                }
                if output.count > 80_000_000 { return Z_MEM_ERROR }
            } while status == Z_OK
            return status
        }
        guard result == Z_STREAM_END else { throw EIXSourceError.invalidResponse }
        return parseISINs(output)
    }

    static func parseISINs(_ csv: Data) -> Set<String> {
        var isins = Set<String>()
        let bytes = [UInt8](csv)
        var lineStart = 0
        for end in bytes.indices where bytes[end] == 10 {
            if let firstComma = bytes[lineStart..<end].firstIndex(of: 44),
               let secondComma = bytes[(firstComma + 1)..<end].firstIndex(of: 44),
               secondComma - firstComma == 13 {
                let code = bytes[(firstComma + 1)..<secondComma]
                if code.prefix(2).allSatisfy({ (65...90).contains($0) }),
                   code.dropFirst(2).dropLast().allSatisfy({ (65...90).contains($0) || (48...57).contains($0) }),
                   code.last.map({ (48...57).contains($0) }) == true {
                    isins.insert(String(decoding: code, as: UTF8.self))
                }
            }
            lineStart = end + 1
        }
        return isins
    }
}

enum EIXSourceError: Error { case missingFile, incompleteFile, invalidResponse }
