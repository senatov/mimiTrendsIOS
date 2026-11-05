import Foundation

protocol DiscoveryCandidateSource: Sendable {
    var sourceID: String { get }
    func loadCandidates() async throws -> [DiscoveryCandidate]
    func refreshIntervalMillis() async -> Int64
}

extension DiscoveryCandidateSource {
    func refreshIntervalMillis() async -> Int64 { 30 * 60_000 }
}

struct DiscoverySnapshot: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let sourceID: String
    let refreshedAtMillis: Int64
    let candidates: [DiscoveryCandidate]

    init(sourceID: String, refreshedAtMillis: Int64, candidates: [DiscoveryCandidate]) {
        schemaVersion = 1
        self.sourceID = sourceID
        self.refreshedAtMillis = refreshedAtMillis
        self.candidates = candidates
    }

    func validate() throws {
        guard schemaVersion == 1, refreshedAtMillis > 0,
              !candidates.isEmpty,
              candidates.count <= DiscoveryCandidateSelector.maximumCandidates,
              candidates.allSatisfy({ $0.sourceID == sourceID }),
              Set(candidates.map(\.identity)).count == candidates.count else {
            throw DiscoveryDataError.invalidSnapshot
        }
        for candidate in candidates { try candidate.validate() }
    }
}

struct DiscoveryRefreshStatus: Sendable {
    let snapshot: DiscoverySnapshot?
    let lastAttemptSucceeded: Bool
    let nextAttemptAtMillis: Int64
    var rankingSources: [RankingSourceHealth] = []

    var isAvailable: Bool { snapshot != nil }

    func hasFreshSnapshot(atMillis nowMillis: Int64) -> Bool {
        guard lastAttemptSucceeded, let snapshot else { return false }
        let age = nowMillis - snapshot.refreshedAtMillis
        return age >= 0 && age < 30 * 60_000 &&
            snapshot.candidates.allSatisfy { candidate in
                let sourceAge = nowMillis - candidate.observedAtMillis
                return sourceAge >= 0 && sourceAge < 30 * 60_000
            }
    }
}

actor DiscoveryRefreshCache {
    private let source: any DiscoveryCandidateSource
    private let nowMillis: @Sendable () -> Int64
    private var snapshot: DiscoverySnapshot?
    private var lastAttemptSucceeded = false
    private var nextAttemptAtMillis: Int64 = 0
    private var inFlight: Task<Void, Never>?
    private var inFlightID: UUID?

    init(source: any DiscoveryCandidateSource,
         nowMillis: @escaping @Sendable () -> Int64 = {
             Int64(Date().timeIntervalSince1970 * 1_000)
         }) {
        self.source = source
        self.nowMillis = nowMillis
    }

    func restore(_ saved: DiscoverySnapshot) throws {
        try saved.validate()
        guard saved.sourceID == source.sourceID else { throw DiscoveryDataError.invalidSnapshot }
        snapshot = saved
        lastAttemptSucceeded = false
        nextAttemptAtMillis = 0
    }

    func cancel() {
        inFlight?.cancel()
        inFlight = nil
        inFlightID = nil
        nextAttemptAtMillis = 0
    }

    func refreshIfNeeded() async -> DiscoveryRefreshStatus {
        if let inFlight {
            await inFlight.value
            return status()
        }
        if nowMillis() >= nextAttemptAtMillis {
            let id = UUID()
            let task = Task { await performRefresh() }
            inFlight = task
            inFlightID = id
            await task.value
            if inFlightID == id {
                inFlight = nil
                inFlightID = nil
            }
        }
        return status()
    }

    private func performRefresh() async {
        AppDiagnostics.shared.record(.info, "Discovery", "refresh-start", "source=\(source.sourceID)")
        do {
            let loaded = try await source.loadCandidates()
            try Task.checkCancellation()
            let selected = try DiscoveryCandidateSelector.select(loaded, sourceID: source.sourceID)
            guard !selected.isEmpty else { throw DiscoveryDataError.invalidCandidate }
            let refreshedAt = nowMillis()
            snapshot = DiscoverySnapshot(
                sourceID: source.sourceID, refreshedAtMillis: refreshedAt, candidates: selected
            )
            lastAttemptSucceeded = true
            nextAttemptAtMillis = refreshedAt + (await source.refreshIntervalMillis())
            AppDiagnostics.shared.record(.info, "Discovery", "refresh-success", "source=\(source.sourceID) received=\(loaded.count) selected=\(selected.count)")
        } catch {
            if Task.isCancelled || error is CancellationError { return }
            lastAttemptSucceeded = false
            nextAttemptAtMillis = nowMillis() + 5 * 60_000
            let failure = error as NSError
            AppDiagnostics.shared.record(.error, "Discovery", "refresh-failed", "source=\(source.sourceID) domain=\(failure.domain) code=\(failure.code)")
        }
    }

    private func status() -> DiscoveryRefreshStatus {
        DiscoveryRefreshStatus(
            snapshot: snapshot,
            lastAttemptSucceeded: lastAttemptSucceeded,
            nextAttemptAtMillis: nextAttemptAtMillis
        )
    }
}
