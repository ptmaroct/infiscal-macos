import Foundation
import AppKit

@MainActor
final class SecretListViewModel: ObservableObject {
    let appViewModel: AppViewModel

    @Published var searchText: String = ""
    @Published var editingSecret: SecretItem?
    @Published var editValue: String = ""
    @Published var editComment: String = ""
    @Published var deletingSecret: SecretItem?
    @Published var isUpdating: Bool = false
    @Published var isDeleting: Bool = false
    @Published var copiedSecretId: String?

    /// Snapshot of sort order at window open — doesn't re-sort on copy
    @Published private var sortedKeyOrder: [String] = []

    init(appViewModel: AppViewModel) {
        self.appViewModel = appViewModel
        snapshotOrder()
    }

    /// Capture the current sort order so copies don't shuffle the list
    func snapshotOrder() {
        sortedKeyOrder = appViewModel.sortedSecrets.map { $0.key }
    }

    /// Secrets in stable order (snapshotted at window open), with new secrets appended
    private var stableSecrets: [SecretItem] {
        let secretsByKey = Dictionary(uniqueKeysWithValues: appViewModel.secrets.map { ($0.key, $0) })
        var result: [SecretItem] = []
        // First: secrets in snapshotted order
        for key in sortedKeyOrder {
            if let secret = secretsByKey[key] {
                result.append(secret)
            }
        }
        // Then: any new secrets not in snapshot
        let snapshotSet = Set(sortedKeyOrder)
        for secret in appViewModel.secrets where !snapshotSet.contains(secret.key) {
            result.append(secret)
        }
        return result
    }

    var filteredSecrets: [SecretItem] {
        let secrets = stableSecrets
        if searchText.isEmpty { return secrets }
        return secrets.filter {
            $0.key.localizedCaseInsensitiveContains(searchText) ||
            ($0.comment?.localizedCaseInsensitiveContains(searchText) ?? false) ||
            ($0.tags?.contains(where: { $0.displayName.localizedCaseInsensitiveContains(searchText) }) ?? false)
        }
    }

    func copy(_ secret: SecretItem) {
        appViewModel.copySecret(secret)
        copiedSecretId = secret.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            if self?.copiedSecretId == secret.id {
                self?.copiedSecretId = nil
            }
        }
    }

    func beginEditing(_ secret: SecretItem) {
        editingSecret = secret
        editValue = secret.value
        editComment = secret.comment ?? ""
    }

    func saveEdit() async -> Bool {
        guard let secret = editingSecret else { return false }
        isUpdating = true
        let success = await appViewModel.updateSecret(secret, newValue: editValue, newComment: editComment)
        isUpdating = false
        if success {
            editingSecret = nil
        }
        return success
    }

    func confirmDelete(_ secret: SecretItem) {
        deletingSecret = secret
    }

    func executeDelete() async -> Bool {
        guard let secret = deletingSecret else { return false }
        isDeleting = true
        let success = await appViewModel.deleteSecret(secret)
        isDeleting = false
        if success {
            deletingSecret = nil
        }
        return success
    }
}
