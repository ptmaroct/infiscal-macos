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

    /// Load secrets via REST API with cache-first strategy
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

        do {
            let fresh = try await InfisicalCLIService.listSecretsViaAPI(
                environment: config.environment,
                projectId: config.projectId,
                secretPath: config.secretPath,
                baseURL: config.baseURL
            )
            secrets = fresh
            cacheSecrets(fresh)
        } catch {
            // Only show error if we have no data to display
            if secrets.isEmpty {
                errorMessage = error.localizedDescription
            }
        }

        isLoading = false
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

    /// Update an existing secret's value and comment
    func updateSecret(_ secret: SecretItem, newValue: String, newComment: String) async -> Bool {
        guard let config = AppConfiguration.load() else { return false }

        do {
            try await InfisicalCLIService.updateSecret(
                name: secret.key,
                value: newValue,
                comment: newComment,
                environment: config.environment,
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

        do {
            try await InfisicalCLIService.deleteSecret(
                name: secret.key,
                environment: config.environment,
                projectId: config.projectId,
                secretPath: config.secretPath,
                baseURL: config.baseURL
            )
            secrets.removeAll { $0.key == secret.key }
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
