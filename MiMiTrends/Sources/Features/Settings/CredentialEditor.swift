import SwiftUI

struct CredentialEditor: View {
    let title: String
    let detail: String
    let load: () throws -> String?
    let save: (String) throws -> Void
    let remove: () throws -> Void
    var onRemove: () -> Void = {}

    @State private var draft = ""
    @State private var hasStoredValue = false
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(SettingsTypography.label).foregroundStyle(.primary)
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
