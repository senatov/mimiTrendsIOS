import SwiftUI

struct WatchlistView: View {
    let onSelect: (String) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    @State private var store: WatchlistStore?
    @State private var entries: [WatchlistEntry] = []
    @State private var newSymbol = ""
    @State private var errorMessage: String?
    @State private var isWorking = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                controls
                    .padding(14)
                List {
                    Section("Saved symbols") {
                        if store == nil && errorMessage == nil {
                            ProgressView("Loading watchlist")
                        } else if entries.isEmpty {
                            ContentUnavailableView("Watchlist is empty", systemImage: "star")
                        } else {
                            ForEach(entries) { entry in
                                WatchlistEntryRow(entry: entry, isWorking: isWorking) {
                                    onSelect(entry.symbol)
                                } onRemove: {
                                    Task { await remove([entry.symbol]) }
                                }
                            }
                            .onDelete { offsets in
                                let symbols = offsets.map { entries[$0].symbol }
                                Task { await remove(symbols) }
                            }
                        }
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }
            .background(TrendsColors.canvas)
            .navigationTitle("Watchlist")
            .task { await load() }
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Watchlist").font(.title2.weight(.regular))
            Text("\(entries.count) saved symbols on this device")
                .font(.caption).foregroundStyle(.secondary)
            controlLayout { addControls }
            Text("Selecting a symbol opens Radar. The feed starts only when you tap Start there.")
                .font(.footnote).foregroundStyle(.secondary)
            if let errorMessage {
                Text(errorMessage).font(.footnote).foregroundStyle(.red)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .trendsPanel()
    }

    private var isCompactControls: Bool {
        #if os(iOS)
        dynamicTypeSize.isAccessibilitySize || horizontalSizeClass == .compact
        #else
        dynamicTypeSize.isAccessibilitySize
        #endif
    }

    private func controlLayout<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        let layout = isCompactControls
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            : AnyLayout(HStackLayout(spacing: 10))
        return layout { content() }
    }

    @ViewBuilder
    private var addControls: some View {
        TextField("Ticker symbol", text: $newSymbol)
            .textFieldStyle(.roundedBorder)
            .autocorrectionDisabled()
            .frame(maxWidth: 240)
            .onSubmit { Task { await add() } }
        TrendsActionButton(title: "Add", systemImage: "plus", tint: .green) {
            Task { await add() }
        }
        .disabled(isWorking || newSymbol.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private func load() async {
        guard store == nil else { return }
        do {
            let opened = try await Task.detached(priority: .userInitiated) {
                try WatchlistStore(url: WatchlistStore.defaultURL())
            }.value
            store = opened
            entries = try await opened.load()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func add() async {
        guard let store, !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            let symbol = try WatchlistStore.normalize(newSymbol)
            let inserted = try await store.add(symbol)
            entries = try await store.load()
            newSymbol = ""
            errorMessage = inserted ? nil : "\(symbol) is already in the watchlist."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func remove(_ symbols: [String]) async {
        guard let store, !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            for symbol in symbols { try await store.remove(symbol) }
            entries = try await store.load()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            if let current = try? await store.load() { entries = current }
        }
    }

}
