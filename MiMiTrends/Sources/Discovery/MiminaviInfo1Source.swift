import Foundation

actor MiminaviInfo1Source: DiscoveryCandidateSource {
    nonisolated let sourceID = "miminavi_info1"
    private let session: URLSession
    private let endpoint: URL

    init(session: URLSession = .shared,
         endpoint: URL = URL(string: "https://miminavi.tech/info1")!) {
        self.session = session
        self.endpoint = endpoint
    }

    func loadCandidates() async throws -> [DiscoveryCandidate] {
        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await BrowserPageRequest.send(request, using: session)
        guard !Task.isCancelled,
              let response = response as? HTTPURLResponse,
              response.statusCode == 200,
              response.url?.scheme == "https",
              response.url?.host == "miminavi.tech",
              response.mimeType == "application/json" else {
            throw DiscoveryDataError.invalidCandidate
        }
        let now = Int64(Date().timeIntervalSince1970 * 1_000)
        return try MiminaviInfo1Decoder.decode(data, sourceID: sourceID, nowMillis: now)
    }
}
