import SwiftUI

struct CredentialEditor: View {
    let title: String
    let detail: String
    let help: CredentialHelp
    let load: () throws -> String?
    let save: (String) throws -> Void
    let remove: () throws -> Void
    var onSave: () -> Void = {}
    var onRemove: () -> Void = {}

    @State private var draft = ""
    @State private var hasStoredValue = false
    @State private var message: String?
    @State private var showingHelp = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text(title).font(SettingsTypography.label).foregroundStyle(.primary)
                Button {
                    showingHelp = true
                } label: {
                    Image(systemName: "questionmark.circle")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Where to get \(title)")
                .popover(isPresented: $showingHelp, arrowEdge: .top) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(help.title).font(.headline)
                        Text(help.message).font(.callout).fixedSize(horizontal: false, vertical: true)
                        if let url = help.url {
                            Link(help.linkTitle, destination: url)
                        }
                    }
                    .padding(16)
                    .frame(width: 320, alignment: .leading)
                }
            }
            Text(detail).font(.callout).foregroundStyle(.secondary)
            SecretEntryField(title: title, value: $draft)
            HStack(spacing: 8) {
                TrendsActionButton(title: "Save", systemImage: "checkmark", tint: .green) {
                    saveDraft()
                }
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if hasStoredValue {
                    TrendsActionButton(title: "Remove", systemImage: "trash", tint: .red,
                                       role: .destructive) {
                        removeStored()
                    }
                }
                Text(hasStoredValue ? storageStatus : "Not configured")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if let message {
                Text(message).font(.callout).foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .foregroundStyle(.primary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SettingsColors.group, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.primary.opacity(0.09), lineWidth: 1)
        }
        .onAppear { reload() }
        .onDisappear { draft = "" }
    }

    private func reload() {
        do {
            draft = try load() ?? ""
            hasStoredValue = !draft.isEmpty
            message = nil
        } catch {
            draft = ""
            hasStoredValue = false
            message = error.localizedDescription
        }
    }

    private func saveDraft() {
        do {
            try save(draft)
            onSave()
            reload()
            message = "Saved on this device."
        } catch {
            message = error.localizedDescription
        }
    }

    private func removeStored() {
        do {
            try remove()
            draft = ""
            hasStoredValue = false
            message = "Removed from this device."
            onRemove()
        } catch {
            message = error.localizedDescription
        }
    }

    private var storageStatus: String {
        #if os(macOS)
        "Saved on this Mac"
        #else
        "Saved in Keychain"
        #endif
    }
}

struct CredentialHelp {
    let title: String
    let message: String
    var linkTitle: String = "Open provider page"
    var url: URL?
}
