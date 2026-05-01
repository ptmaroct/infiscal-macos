import Foundation
import KuberaCore
import AppKit

@MainActor
final class SecretListViewModel: ObservableObject {
    let appViewModel: AppViewModel

    @Published var searchText: String = ""
    @Published var selectedProjectId: String?
    @Published var selectedEnvironment: String?
    @Published var editingSecret: SecretItem?
    @Published var editValue: String = ""
    @Published var editComment: String = ""
    @Published var editExpiryDate: Date? = nil
    @Published var editServiceURL: String = ""
    @Published var deletingSecret: SecretItem?
    @Published var isUpdating: Bool = false
    @Published var isDeleting: Bool = false
    @Published var copiedSecretId: String?

    /// Snapshot of sort order at window open — doesn't re-sort on copy.
    /// Use a compound identity because all-environment mode can contain the
    /// same secret key in multiple environments.
    @Published private var sortedSecretOrder: [String] = []

    init(appViewModel: AppViewModel) {
        self.appViewModel = appViewModel
        snapshotOrder()
    }

    /// Capture the current sort order so copies don't shuffle the list
    func snapshotOrder() {
        sortedSecretOrder = appViewModel.sortedSecrets.map(\.stableListIdentity)
    }

    /// Secrets in stable order (snapshotted at window open), with new secrets appended
    private var stableSecrets: [SecretItem] {
        let secretsByIdentity = Dictionary(
            appViewModel.secrets.map { ($0.stableListIdentity, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var result: [SecretItem] = []
        // First: secrets in snapshotted order
        for identity in sortedSecretOrder {
            if let secret = secretsByIdentity[identity] {
                result.append(secret)
            }
        }
        // Then: any new secrets not in snapshot
        let snapshotSet = Set(sortedSecretOrder)
        for secret in appViewModel.secrets where !snapshotSet.contains(secret.stableListIdentity) {
            result.append(secret)
        }
        return result
    }

    var projectFilters: [SecretProjectFilter] {
        Dictionary(grouping: stableSecrets, by: { $0.projectFilterId })
            .map { id, secrets in
                SecretProjectFilter(
                    id: id,
                    name: secrets.first?.projectName ?? AppConfiguration.load()?.projectName ?? "Project",
                    count: secrets.count
                )
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var environmentFilters: [SecretEnvironmentFilter] {
        let source = stableSecrets.filter {
            selectedProjectId == nil || $0.projectFilterId == selectedProjectId
        }
        return Dictionary(grouping: source, by: { $0.environment ?? AppConfiguration.defaultEnvironment })
            .map { slug, secrets in
                SecretEnvironmentFilter(slug: slug, count: secrets.count)
            }
            .sorted { lhs, rhs in
                let rank = ["prod": 0, "production": 0, "staging": 1, "stage": 1, "stg": 1, "dev": 2, "development": 2]
                let lhsRank = rank[lhs.slug.lowercased()] ?? 10
                let rhsRank = rank[rhs.slug.lowercased()] ?? 10
                if lhsRank != rhsRank { return lhsRank < rhsRank }
                return lhs.slug.localizedCaseInsensitiveCompare(rhs.slug) == .orderedAscending
            }
    }

    var activeFilterCount: Int {
        [selectedProjectId, selectedEnvironment].compactMap { $0 }.count
    }

    var isFiltering: Bool {
        !searchText.isEmpty || selectedProjectId != nil || selectedEnvironment != nil
    }

    var filteredCount: Int {
        filteredSecrets.count
    }

    var totalCount: Int {
        stableSecrets.count
    }

    var environmentFilterTotalCount: Int {
        stableSecrets.filter {
            selectedProjectId == nil || $0.projectFilterId == selectedProjectId
        }.count
    }

    var filteredSecrets: [SecretItem] {
        stableSecrets.filter { secret in
            let matchesProject = selectedProjectId == nil || secret.projectFilterId == selectedProjectId
            let matchesEnvironment = selectedEnvironment == nil || secret.environment == selectedEnvironment
            let matchesSearch = searchText.isEmpty
                || secret.key.localizedCaseInsensitiveContains(searchText)
                || (secret.comment?.localizedCaseInsensitiveContains(searchText) ?? false)
                || (secret.tags?.contains(where: { $0.displayName.localizedCaseInsensitiveContains(searchText) }) ?? false)

            return matchesProject && matchesEnvironment && matchesSearch
        }
    }

    func clearFilters() {
        searchText = ""
        selectedProjectId = nil
        selectedEnvironment = nil
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
        editExpiryDate = secret.expiryDate
        editServiceURL = secret.serviceURL?.absoluteString ?? ""
    }

    func saveEdit() async -> Bool {
        guard let secret = editingSecret else { return false }
        isUpdating = true
        let trimmedURL = editServiceURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let urlArg: String? = trimmedURL.isEmpty ? nil : trimmedURL
        let success = await appViewModel.updateSecret(
            secret,
            newValue: editValue,
            newComment: editComment,
            newExpiry: editExpiryDate,
            newServiceURL: urlArg
        )
        isUpdating = false
        if success {
            // Reschedule notifications immediately for this (id, env).
            let configEnv = AppConfiguration.load()?.environment ?? AppConfiguration.defaultEnvironment
            let envForSchedule = secret.environment ?? configEnv
            if envForSchedule != AppConfiguration.allEnvironmentsSentinel {
                let updated = SecretItem(
                    id: secret.id,
                    key: secret.key,
                    value: editValue,
                    type: secret.type,
                    comment: editComment,
                    version: secret.version,
                    tags: secret.tags,
                    secretMetadata: buildSecretMetadataPayload(
                        expiryDate: editExpiryDate, serviceURL: urlArg
                    ).map { SecretMetadataEntry(key: $0["key"] ?? "", value: $0["value"] ?? "") },
                    createdAt: secret.createdAt,
                    updatedAt: secret.updatedAt,
                    environment: envForSchedule
                )
                ExpiryNotificationScheduler.shared.schedule(secret: updated, environment: envForSchedule)
            }
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

extension SecretItem {
    var stableListIdentity: String {
        "\(projectFilterId):\(environment ?? AppConfiguration.defaultEnvironment):\(id):\(key)"
    }

    var projectFilterId: String {
        projectId ?? AppConfiguration.load()?.projectId ?? "current"
    }
}

struct SecretProjectFilter: Identifiable, Hashable {
    let id: String
    let name: String
    let count: Int
}

struct SecretEnvironmentFilter: Identifiable, Hashable {
    let slug: String
    let count: Int

    var id: String { slug }
}
