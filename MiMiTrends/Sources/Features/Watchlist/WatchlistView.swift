import SwiftUI

struct WatchlistView: View {
    let onSelect: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    @State private var store: WatchlistStore?
    @State private var entries: [WatchlistEntry] = []
    @State private var newSymbol = ""
    @State private var errorMessage: String?
    @State private var isWorking = false
    @State private var editingSymbol: String?
    @State private var editedSymbol = ""

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
                                if editingSymbol == entry.symbol {
                                    editRow(entry)
                                } else {
                                    WatchlistEntryRow(entry: entry, isWorking: isWorking) {
                                        onSelect(entry.symbol)
                                    } onEdit: {
                                        editingSymbol = entry.symbol
                                        editedSymbol = entry.symbol
                                        errorMessage = nil
                                    } onRemove: {
                                        Task { await remove([entry.symbol]) }
                                    }
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
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .frame(minHeight: 220)
            }
            .background(TrendsColors.canvas)
            .navigationTitle("Watchlist")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    TrendsActionButton(title: "Done", systemImage: "checkmark") { dismiss() }
                }
            }
            .task { await load() }
        }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 420)
        #endif
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
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
        .disabled(store == nil || isWorking || newSymbol.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private func editRow(_ entry: WatchlistEntry) -> some View {
        HStack(spacing: 8) {
            TextField("Ticker symbol", text: $editedSymbol)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .accessibilityLabel("Edit \(entry.symbol) ticker symbol")
                .onSubmit { Task { await rename(entry.symbol) } }
            TrendsActionButton(title: "Save", systemImage: "checkmark", tint: .green) {
                Task { await rename(entry.symbol) }
            }
            .disabled(isWorking || editedSymbol.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            TrendsActionButton(title: "Cancel", systemImage: "xmark") {
                editingSymbol = nil
                errorMessage = nil
            }
            .disabled(isWorking)
        }
        .padding(.vertical, 4)
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

    private func rename(_ original: String) async {
        guard let store, !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            try await store.rename(original, to: editedSymbol)
            entries = try await store.load()
            editingSymbol = nil
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

}
