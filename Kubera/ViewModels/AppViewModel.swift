import Foundation
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

        let envSlugs: [String]
        if config.isAllEnvironments {
            envSlugs = await resolveProjectEnvSlugs(projectId: config.projectId,
                                                   baseURL: config.baseURL)
            if envSlugs.isEmpty {
                errorMessage = "Project has no environments"
                isLoading = false
                return
            }
        } else {
            envSlugs = [config.environment]
        }

        do {
            let merged = try await fetchSecrets(
                envSlugs: envSlugs,
                projectId: config.projectId,
                secretPath: config.secretPath,
                baseURL: config.baseURL
            )
            secrets = merged
            cacheSecrets(merged)
            for env in envSlugs {
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

    /// Fetch secrets across one or more env slugs. Each result has `environment` set.
    private func fetchSecrets(
        envSlugs: [String],
        projectId: String,
        secretPath: String,
        baseURL: String
    ) async throws -> [SecretItem] {
        try await withThrowingTaskGroup(of: (String, [SecretItem]).self) { group in
            for env in envSlugs {
                group.addTask {
                    let items = try await InfisicalCLIService.listSecretsViaAPI(
                        environment: env,
                        projectId: projectId,
                        secretPath: secretPath,
                        baseURL: baseURL
                    )
                    let tagged = items.map { item -> SecretItem in
                        var copy = item
                        copy.environment = env
                        return copy
                    }
                    return (env, tagged)
                }
            }

            var collected: [(String, [SecretItem])] = []
            for try await result in group {
                collected.append(result)
            }
            // Preserve env ordering from envSlugs for stable display.
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

        do {
            try await InfisicalCLIService.createSecret(
                key: key,
                value: value,
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
        newServiceURL: String?
    ) async -> Bool {
        guard let config = AppConfiguration.load() else { return false }
        // In all-envs mode the per-secret env is the source of truth.
        let env = secret.environment ?? config.environment
        guard env != AppConfiguration.allEnvironmentsSentinel else { return false }

        do {
            try await InfisicalCLIService.updateSecret(
                name: secret.key,
                value: newValue,
                comment: newComment,
                expiryDate: newExpiry,
                serviceURL: newServiceURL,
                metadataExplicit: true,
                environment: env,
                projectId: config.projectId,
                secretPath: config.secretPath,
                baseURL: config.baseURL
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
        guard env != AppConfiguration.allEnvironmentsSentinel else { return false }

        do {
            try await InfisicalCLIService.deleteSecret(
                name: secret.key,
                environment: env,
                projectId: config.projectId,
                secretPath: config.secretPath,
                baseURL: config.baseURL
            )
            // In all-envs mode keep entries from other envs intact.
            secrets.removeAll { $0.key == secret.key && ($0.environment ?? env) == env }
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
