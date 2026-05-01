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
    @Published var editTags: [InfisicalTag] = []
    @Published var editSelectedTagIds: Set<String> = []
    @Published var editPendingTagNames: [String] = []
    @Published var editNewTagName: String = ""
    @Published var editIsLoadingTags: Bool = false
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
        editSelectedTagIds = Set((secret.tags ?? []).map(\.id))
        editPendingTagNames = []
        editNewTagName = ""

        let projectId = secret.projectId ?? AppConfiguration.load()?.projectId
        guard let projectId, !projectId.isEmpty else {
            editTags = []
            return
        }
        let cached = ProjectCache.shared.cachedTags(for: projectId)
        editTags = cached
        if cached.isEmpty { editIsLoadingTags = true }
        Task { [weak self] in
            let fresh = await ProjectCache.shared.fetchTags(for: projectId)
            guard let self else { return }
            self.editTags = fresh
            self.editIsLoadingTags = false
        }
    }

    func toggleEditTag(_ tag: InfisicalTag) {
        if editSelectedTagIds.contains(tag.id) {
            editSelectedTagIds.remove(tag.id)
        } else {
            editSelectedTagIds.insert(tag.id)
        }
    }

    func queueEditTag() {
        let name = editNewTagName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        if let existing = editTags.first(where: { $0.displayName.lowercased() == name.lowercased() }) {
            editSelectedTagIds.insert(existing.id)
            editNewTagName = ""
            return
        }
        if editPendingTagNames.contains(where: { $0.lowercased() == name.lowercased() }) {
            editNewTagName = ""
            return
        }
        editPendingTagNames.append(name)
        editNewTagName = ""
    }

    func removeEditPendingTag(_ name: String) {
        editPendingTagNames.removeAll { $0 == name }
    }

    func saveEdit() async -> Bool {
        guard let secret = editingSecret else { return false }
        isUpdating = true
        let trimmedURL = editServiceURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let urlArg: String? = trimmedURL.isEmpty ? nil : trimmedURL

        // Materialize any pending tag names into real tags first.
        let projectId = secret.projectId ?? AppConfiguration.load()?.projectId ?? ""
        let baseURL = AppConfiguration.load()?.baseURL ?? AppConfiguration.defaultBaseURL
        var allTagIds = editSelectedTagIds
        if !editPendingTagNames.isEmpty, !projectId.isEmpty {
            let names = editPendingTagNames
            await withTaskGroup(of: InfisicalTag?.self) { group in
                for name in names {
                    group.addTask {
                        try? await InfisicalCLIService.createTag(
                            name: name, projectId: projectId, baseURL: baseURL
                        )
                    }
                }
                for await result in group {
                    if let newTag = result {
                        allTagIds.insert(newTag.id)
                        editTags.append(newTag)
                        ProjectCache.shared.addTag(newTag, for: projectId)
                    }
                }
            }
            editPendingTagNames = []
        }

        let success = await appViewModel.updateSecret(
            secret,
            newValue: editValue,
            newComment: editComment,
            newExpiry: editExpiryDate,
            newServiceURL: urlArg,
            newTagIds: Array(allTagIds)
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
