import Foundation

actor DiscoveryPoolController {
    private let cache: DiscoveryRefreshCache
    private var restored = false
    private var preferences = RadarDiscoveryPreferences.load()
    private var lastSavedAtMillis: Int64?

    init() {
        cache = DiscoveryRefreshCache(source: WallstreetDiscoverySource.shared)
    }

    func refresh() async -> DiscoveryRefreshStatus {
        if !restored {
            restored = true
            if let store = try? snapshotStore(),
               let saved = try? await store.load() {
                try? await cache.restore(saved)
                lastSavedAtMillis = saved.refreshedAtMillis
            }
        }
        let current = RadarDiscoveryPreferences.load()
        if preferences != current { preferences = current; await cache.cancel() }
        var status = await cache.refreshIfNeeded()
        status.rankingSources = await WallstreetDiscoverySource.shared.health()
        if status.lastAttemptSucceeded, let snapshot = status.snapshot,
           lastSavedAtMillis != snapshot.refreshedAtMillis,
           let store = try? snapshotStore() {
            if (try? await store.save(snapshot)) != nil {
                lastSavedAtMillis = snapshot.refreshedAtMillis
            }
        }
        return status
    }

    func stop() async {
        await cache.cancel()
    }

    private func snapshotStore() throws -> DiscoverySnapshotStore {
        DiscoverySnapshotStore(url: try DiscoverySnapshotStore.defaultURL(for: "wallstreet_rankings"))
    }
}
