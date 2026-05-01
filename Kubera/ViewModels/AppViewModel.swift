import Foundation
import KuberaCore
import AppKit

@MainActor
final class AppViewModel: ObservableObject {
    @Published var secrets: [SecretItem] = []
    @Published var searchText: String = ""
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var isConfigured: Bool = false

    /// Copy counts persisted in UserDefaults
    private var copyCounts: [String: Int] = [:]
    private static let copyCountsKey = "infisical_copy_counts"
    private static let secretsCacheKey = "infisical_secrets_cache"

    /// Max items to show in menubar when not searching
    static let menubarMaxItems = 5

    init() {
        isConfigured = AppConfiguration.load() != nil
        loadCopyCounts()
        loadCachedSecrets()
    }

    /// Secrets sorted by most-copied first, then alphabetical
    var sortedSecrets: [SecretItem] {
        secrets.sorted { a, b in
            let countA = copyCounts[a.key] ?? 0
            let countB = copyCounts[b.key] ?? 0
            if countA != countB { return countA > countB }
            return a.key < b.key
        }
    }

    /// Filtered (by search), sorted by most-copied
    var filteredSecrets: [SecretItem] {
        let sorted = sortedSecrets
        if searchText.isEmpty { return sorted }
        return sorted.filter {
            $0.key.localizedCaseInsensitiveContains(searchText)
        }
    }

    /// Top N secrets for the menubar (when not searching)
    var menubarSecrets: [SecretItem] {
        if !searchText.isEmpty {
            return filteredSecrets
        }
        return Array(sortedSecrets.prefix(Self.menubarMaxItems))
    }

    /// How many secrets are hidden in the menubar
    var hiddenCount: Int {
        max(0, secrets.count - Self.menubarMaxItems)
    }

    /// Copy count for a given key
    func copyCount(for key: String) -> Int {
        copyCounts[key] ?? 0
    }

    /// Load secrets via REST API with cache-first strategy.
    /// When `config.environment == "*"` (all-envs mode), fetches every env defined
    /// on the selected project in parallel and tags each `SecretItem.environment`.
    func loadSecrets() async {
        guard let config = AppConfiguration.load() else {
            isConfigured = false
            return
        }

        let hadCachedData = !secrets.isEmpty
        if !hadCachedData {
            isLoading = true
        }
        errorMessage = nil

        // Resolve which (project, env) pairs to fetch. All-projects mode fans out
        // across every cached project; otherwise we use the single configured project.
        var fetchTargets: [(projectId: String, projectName: String?, envSlugs: [String])] = []
        if config.isAllProjects {
            let projects = ProjectCache.shared.projects.isEmpty
                ? await ProjectCache.shared.fetchProjects()
                : ProjectCache.shared.projects
            for project in projects {
                let slugs = project.environments.map { $0.slug }
                guard !slugs.isEmpty else { continue }
                fetchTargets.append((project.id, project.name, slugs))
            }
            if fetchTargets.isEmpty {
                errorMessage = "No projects available"
                isLoading = false
                return
            }
        } else if config.isAllEnvironments {
            let envSlugs = await resolveProjectEnvSlugs(projectId: config.projectId,
                                                        baseURL: config.baseURL)
            if envSlugs.isEmpty {
                errorMessage = "Project has no environments"
                isLoading = false
                return
            }
            fetchTargets.append((config.projectId, config.projectName, envSlugs))
        } else {
            fetchTargets.append((config.projectId, config.projectName, [config.environment]))
        }

        let store = SecretStoreFactory.make(for: config)
        do {
            var merged: [SecretItem] = []
            for target in fetchTargets {
                let items = try await fetchSecrets(
                    store: store,
                    envSlugs: target.envSlugs,
                    projectId: target.projectId,
                    projectName: target.projectName,
                    secretPath: config.secretPath
                )
                merged.append(contentsOf: items)
            }
            secrets = merged
            cacheSecrets(merged)
            // Reconcile expiry notifications per (env) bucket. Across multiple
            // projects the same env slug aggregates — fine for notification
            // dedup since reconcile keys on secret key + env.
            let allEnvs = Set(fetchTargets.flatMap { $0.envSlugs })
            for env in allEnvs {
                let envSecrets = merged.filter { $0.environment == env }
                ExpiryNotificationScheduler.shared.reconcile(
                    secrets: envSecrets, environment: env
                )
            }
        } catch {
            // Only show error if we have no data to display
            if secrets.isEmpty {
                errorMessage = error.localizedDescription
            }
        }

        isLoading = false
    }

    /// Fetch secrets across one or more env slugs through the active backend.
    /// Each returned `SecretItem.environment` is stamped client-side.
    private func fetchSecrets(
        store: SecretStore,
        envSlugs: [String],
        projectId: String,
        projectName: String?,
        secretPath: String
    ) async throws -> [SecretItem] {
        try await withThrowingTaskGroup(of: (String, [SecretItem]).self) { group in
            for env in envSlugs {
                group.addTask {
                    let items = try await store.listSecrets(
                        environment: env,
                        projectId: projectId,
                        secretPath: secretPath
                    )
                    let tagged = items.map { item -> SecretItem in
                        var copy = item
                        copy.environment = env
                        copy.projectId = projectId
                        copy.projectName = projectName
                        return copy
                    }
                    return (env, tagged)
                }
            }

            var collected: [(String, [SecretItem])] = []
            for try await result in group {
                collected.append(result)
            }
            let order = Dictionary(uniqueKeysWithValues: envSlugs.enumerated().map { ($1, $0) })
            collected.sort { (order[$0.0] ?? 0) < (order[$1.0] ?? 0) }
            return collected.flatMap { $0.1 }
        }
    }

    /// Look up env slugs for a project (cache-first, then fetch).
    private func resolveProjectEnvSlugs(projectId: String, baseURL: String) async -> [String] {
        if let project = ProjectCache.shared.projects.first(where: { $0.id == projectId }) {
            return project.environments.map { $0.slug }
        }
        let fresh = await ProjectCache.shared.fetchProjects()
        return fresh.first(where: { $0.id == projectId })?.environments.map { $0.slug } ?? []
    }

    func copySecret(_ secret: SecretItem) {
        ClipboardService.copy(secret.value)
        copyCounts[secret.key, default: 0] += 1
        saveCopyCounts()
    }

    func createSecret(key: String, value: String) async -> Bool {
        guard let config = AppConfiguration.load() else { return false }
        let store = SecretStoreFactory.make(for: config)
        do {
            try await store.createSecret(
                name: key, value: value, comment: "", tagIds: [],
                expiryDate: nil, serviceURL: nil,
                environment: config.environment,
                projectId: config.projectId,
                secretPath: config.secretPath
            )
            await loadSecrets()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// Update an existing secret's value, comment, expiry, and service URL.
    /// Pass nil for `newExpiry` / `newServiceURL` to clear them (metadata is rewritten on every save).
    func updateSecret(
        _ secret: SecretItem,
        newValue: String,
        newComment: String,
        newExpiry: Date?,
        newServiceURL: String?,
        newTagIds: [String]? = nil
    ) async -> Bool {
        guard let config = AppConfiguration.load() else { return false }
        // In all-envs mode the per-secret env is the source of truth.
        let env = secret.environment ?? config.environment
        let projectId = secret.projectId ?? config.projectId
        guard env != AppConfiguration.allEnvironmentsSentinel else { return false }

        let store = SecretStoreFactory.make(for: config)
        do {
            try await store.updateSecret(
                name: secret.key,
                value: newValue,
                comment: newComment,
                tagIds: newTagIds ?? [],
                tagsExplicit: newTagIds != nil,
                expiryDate: newExpiry,
                serviceURL: newServiceURL,
                metadataExplicit: true,
                environment: env,
                projectId: projectId,
                secretPath: config.secretPath
            )
            await loadSecrets()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// Delete a secret
    func deleteSecret(_ secret: SecretItem) async -> Bool {
        guard let config = AppConfiguration.load() else { return false }
        let env = secret.environment ?? config.environment
        let projectId = secret.projectId ?? config.projectId
        guard env != AppConfiguration.allEnvironmentsSentinel else { return false }
        let store = SecretStoreFactory.make(for: config)
        do {
            try await store.deleteSecret(
                name: secret.key,
                environment: env,
                projectId: projectId,
                secretPath: config.secretPath
            )
            // In all-envs mode keep entries from other envs intact.
            secrets.removeAll {
                $0.key == secret.key
                    && ($0.environment ?? env) == env
                    && ($0.projectId ?? projectId) == projectId
            }
            cacheSecrets(secrets)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func configurationSaved() {
        isConfigured = true
        Task {
            await loadSecrets()
        }
    }

    // MARK: - Secrets Cache (UserDefaults)

    private func loadCachedSecrets() {
        guard let data = UserDefaults.standard.data(forKey: Self.secretsCacheKey),
              let cached = try? JSONDecoder().decode([SecretItem].self, from: data) else { return }
        secrets = cached
    }

    private func cacheSecrets(_ items: [SecretItem]) {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: Self.secretsCacheKey)
        }
    }

    // MARK: - Copy Counts Persistence

    private func loadCopyCounts() {
        if let data = UserDefaults.standard.data(forKey: Self.copyCountsKey),
           let decoded = try? JSONDecoder().decode([String: Int].self, from: data) {
            copyCounts = decoded
        }
    }

    private func saveCopyCounts() {
        if let data = try? JSONEncoder().encode(copyCounts) {
            UserDefaults.standard.set(data, forKey: Self.copyCountsKey)
        }
    }
}
