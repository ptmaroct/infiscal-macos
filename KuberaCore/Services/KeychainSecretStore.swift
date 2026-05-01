import Foundation
import CryptoKit
import Security

/// Local secret store backed by an encrypted JSON file in Application Support.
///
/// File: `~/Library/Application Support/Kubera/local-store.kbra`
/// Encryption: AES-256-GCM with a 256-bit master key stored in the macOS Keychain
/// (service `com.kubera.local`, account `master-key`). The master key is generated
/// once on first use and stays on this device unless the user enables iCloud sync.
///
/// Layout of the decrypted JSON: `LocalStore` — projects, secrets, tags. There is
/// one synthetic project (`localProjectId`) with three default environments
/// (`dev`, `stg`, `prod`) so the existing UI/CLI can address it like an Infisical
/// project. Users can rename or add envs later via Settings.
public actor KeychainSecretStore: SecretStore {
    public nonisolated let id = SecretStoreBackendID.local
    public nonisolated let displayName = "On this Mac"

    /// Synthetic project ID used when the local backend is active. Stored in
    /// `AppConfiguration.projectId` so call sites that key on projectId still work.
    public static let localProjectId = "local"
    public static let defaultEnvironments = ["dev", "staging", "prod"]
    public static let defaultEnvironmentNames = ["dev": "Development",
                                                 "staging": "Staging",
                                                 "prod": "Production"]

    private static let keychainService = "com.kubera.local"
    private static let masterKeyAccount = "master-key"

    private let fileURL: URL
    private var cache: LocalStore?

    public init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory,
                                                      in: .userDomainMask)[0]
            self.fileURL = appSupport
                .appendingPathComponent("Kubera", isDirectory: true)
                .appendingPathComponent("local-store.kbra")
        }
    }

    // MARK: - SecretStore

    public func isReady() async -> Bool { true }

    public func listSecrets(environment: String, projectId: String,
                            secretPath: String) async throws -> [SecretItem] {
        let store = try loadOrInit()
        return store.secrets
            .filter { $0.matches(projectId: projectId, environment: environment, path: secretPath) }
            .map { $0.toSecretItem() }
            .sorted { $0.key < $1.key }
    }

    public func createSecret(
        name: String, value: String, comment: String, tagIds: [String],
        expiryDate: Date?, serviceURL: String?,
        environment: String, projectId: String, secretPath: String
    ) async throws {
        var store = try loadOrInit()
        if store.secrets.contains(where: {
            $0.matches(projectId: projectId, environment: environment, path: secretPath)
                && $0.key == name
        }) {
            throw LocalStoreError.duplicateKey(name)
        }
        let now = ISO8601DateFormatter().string(from: Date())
        let metadata = LocalSecretRecord.buildMetadata(expiryDate: expiryDate, serviceURL: serviceURL)
        let record = LocalSecretRecord(
            id: UUID().uuidString,
            projectId: projectId,
            environment: environment,
            secretPath: secretPath,
            key: name,
            value: value,
            comment: comment.isEmpty ? nil : comment,
            tagIds: tagIds,
            secretMetadata: metadata,
            createdAt: now,
            updatedAt: now
        )
        store.secrets.append(record)
        try save(store)
    }

    public func updateSecret(
        name: String, value: String, comment: String, tagIds: [String],
        tagsExplicit: Bool,
        expiryDate: Date?, serviceURL: String?, metadataExplicit: Bool,
        environment: String, projectId: String, secretPath: String
    ) async throws {
        var store = try loadOrInit()
        guard let idx = store.secrets.firstIndex(where: {
            $0.matches(projectId: projectId, environment: environment, path: secretPath)
                && $0.key == name
        }) else {
            throw LocalStoreError.notFound(name)
        }
        var rec = store.secrets[idx]
        rec.value = value
        rec.comment = comment.isEmpty ? nil : comment
        if tagsExplicit { rec.tagIds = tagIds }
        if metadataExplicit {
            rec.secretMetadata = LocalSecretRecord.buildMetadata(
                expiryDate: expiryDate, serviceURL: serviceURL
            )
        }
        rec.updatedAt = ISO8601DateFormatter().string(from: Date())
        store.secrets[idx] = rec
        try save(store)
    }

    public func deleteSecret(name: String, environment: String,
                             projectId: String, secretPath: String) async throws {
        var store = try loadOrInit()
        let before = store.secrets.count
        store.secrets.removeAll {
            $0.matches(projectId: projectId, environment: environment, path: secretPath)
                && $0.key == name
        }
        if store.secrets.count == before {
            throw LocalStoreError.notFound(name)
        }
        try save(store)
    }

    public func listProjects() async throws -> [InfisicalProject] {
        let store = try loadOrInit()
        return store.projects.map { p in
            InfisicalProject(
                id: p.id, name: p.name, slug: p.id,
                environments: p.environments.map {
                    InfisicalEnvironment(name: $0.name, slug: $0.slug)
                }
            )
        }
    }

    public func listTags(projectId: String) async throws -> [InfisicalTag] {
        let store = try loadOrInit()
        return store.tags.filter { $0.projectId == projectId }.map { $0.toInfisical() }
    }

    public func createTag(name: String, color: String,
                          projectId: String) async throws -> InfisicalTag {
        var store = try loadOrInit()
        let slug = Self.slugify(name)
        if let existing = store.tags.first(where: { $0.projectId == projectId && $0.slug == slug }) {
            return existing.toInfisical()
        }
        let tag = LocalTag(
            id: UUID().uuidString, projectId: projectId,
            slug: slug, name: name, color: color
        )
        store.tags.append(tag)
        try save(store)
        return tag.toInfisical()
    }

    public func createProject(name: String) async throws -> InfisicalProject {
        var store = try loadOrInit()
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw LocalStoreError.invalidName("Project name cannot be empty")
        }
        let id = Self.slugify(trimmed)
        if store.projects.contains(where: { $0.id == id }) {
            throw LocalStoreError.duplicateKey(trimmed)
        }
        let envs = Self.defaultEnvironments.map {
            LocalEnvironment(slug: $0,
                             name: Self.defaultEnvironmentNames[$0] ?? $0.capitalized)
        }
        let project = LocalProject(id: id, name: trimmed, environments: envs)
        store.projects.append(project)
        try save(store)
        return InfisicalProject(
            id: project.id, name: project.name, slug: project.id,
            environments: project.environments.map {
                InfisicalEnvironment(name: $0.name, slug: $0.slug)
            }
        )
    }

    public func createEnvironment(name: String, slug: String,
                                  projectId: String) async throws -> InfisicalEnvironment {
        var store = try loadOrInit()
        guard let pIdx = store.projects.firstIndex(where: { $0.id == projectId }) else {
            throw LocalStoreError.notFound(projectId)
        }
        let cleanSlug = Self.slugify(slug.isEmpty ? name : slug)
        guard !cleanSlug.isEmpty else {
            throw LocalStoreError.invalidName("Environment slug cannot be empty")
        }
        if store.projects[pIdx].environments.contains(where: { $0.slug == cleanSlug }) {
            throw LocalStoreError.duplicateKey(cleanSlug)
        }
        let env = LocalEnvironment(slug: cleanSlug,
                                   name: name.trimmingCharacters(in: .whitespacesAndNewlines))
        store.projects[pIdx].environments.append(env)
        try save(store)
        return InfisicalEnvironment(name: env.name, slug: env.slug)
    }

    // MARK: - Backup helpers

    /// Snapshot every secret as `BackupSecret` records for archive export.
    public func exportAll() async throws -> [BackupSecret] {
        let store = try loadOrInit()
        return store.secrets.map { rec in
            BackupSecret(
                key: rec.key, value: rec.value, comment: rec.comment,
                tags: rec.tagIds.compactMap { tagId in
                    store.tags.first(where: { $0.id == tagId }).map { $0.toSecretTag() }
                },
                secretMetadata: rec.secretMetadata,
                environment: rec.environment, projectId: rec.projectId,
                secretPath: rec.secretPath
            )
        }
    }

    /// Restore from a backup archive into the local store. Existing entries with
    /// the same `(projectId, env, path, key)` are overwritten when `overwrite`
    /// is true; otherwise duplicates are skipped.
    @discardableResult
    public func importBackup(_ items: [BackupSecret], overwrite: Bool) async throws -> Int {
        var store = try loadOrInit()
        var imported = 0
        let now = ISO8601DateFormatter().string(from: Date())
        for item in items {
            ensureEnvironment(slug: item.environment, in: &store, projectId: item.projectId)
            if let idx = store.secrets.firstIndex(where: {
                $0.matches(projectId: item.projectId, environment: item.environment,
                           path: item.secretPath) && $0.key == item.key
            }) {
                guard overwrite else { continue }
                var rec = store.secrets[idx]
                rec.value = item.value
                rec.comment = item.comment
                rec.secretMetadata = item.secretMetadata
                rec.updatedAt = now
                store.secrets[idx] = rec
            } else {
                let rec = LocalSecretRecord(
                    id: UUID().uuidString,
                    projectId: item.projectId,
                    environment: item.environment,
                    secretPath: item.secretPath,
                    key: item.key,
                    value: item.value,
                    comment: item.comment,
                    tagIds: [],
                    secretMetadata: item.secretMetadata,
                    createdAt: now,
                    updatedAt: now
                )
                store.secrets.append(rec)
            }
            imported += 1
        }
        try save(store)
        return imported
    }

    private func ensureEnvironment(slug: String, in store: inout LocalStore,
                                   projectId: String) {
        guard let pIdx = store.projects.firstIndex(where: { $0.id == projectId }) else { return }
        if !store.projects[pIdx].environments.contains(where: { $0.slug == slug }) {
            store.projects[pIdx].environments.append(
                LocalEnvironment(slug: slug, name: slug.capitalized)
            )
        }
    }

    // MARK: - Persistence

    private func loadOrInit() throws -> LocalStore {
        if let cache { return cache }
        if FileManager.default.fileExists(atPath: fileURL.path) {
            let key = try Self.loadOrCreateMasterKey()
            let blob = try Data(contentsOf: fileURL)
            let json = try LocalCrypto.open(blob, key: key)
            let decoded = try JSONDecoder().decode(LocalStore.self, from: json)
            cache = decoded
            return decoded
        }
        let fresh = LocalStore.bootstrap()
        try save(fresh)
        return fresh
    }

    private func save(_ store: LocalStore) throws {
        let key = try Self.loadOrCreateMasterKey()
        let json = try JSONEncoder().encode(store)
        let blob = try LocalCrypto.seal(json, key: key)
        let dir = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try blob.write(to: fileURL, options: .atomic)
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600], ofItemAtPath: fileURL.path
        )
        cache = store
    }

    // MARK: - Master key

    /// Read the master key from Keychain, creating one on first use.
    public static func loadOrCreateMasterKey() throws -> SymmetricKey {
        if let existing = try fetchMasterKey() {
            return SymmetricKey(data: existing)
        }
        let fresh = LocalCrypto.randomBytes(32)
        try storeMasterKey(fresh)
        return SymmetricKey(data: fresh)
    }

    private static func fetchMasterKey() throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: masterKeyAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        if status != errSecSuccess {
            throw LocalStoreError.keychainFailed(Int(status))
        }
        return item as? Data
    }

    private static func storeMasterKey(_ data: Data) throws {
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: masterKeyAccount,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status != errSecSuccess && status != errSecDuplicateItem {
            throw LocalStoreError.keychainFailed(Int(status))
        }
    }

    /// Wipe the master key + on-disk store. Used by Settings "Reset local store".
    public static func wipe(fileURL: URL? = nil) throws {
        let url = fileURL ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Kubera", isDirectory: true)
            .appendingPathComponent("local-store.kbra")
        try? FileManager.default.removeItem(at: url)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: masterKeyAccount
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Helpers

    private static func slugify(_ s: String) -> String {
        s.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "[^a-z0-9\\-]", with: "", options: .regularExpression)
    }
}

// MARK: - Stored model

public enum LocalStoreError: LocalizedError {
    case duplicateKey(String)
    case notFound(String)
    case keychainFailed(Int)
    case invalidName(String)

    public var errorDescription: String? {
        switch self {
        case .duplicateKey(let k): return "'\(k)' already exists."
        case .notFound(let k): return "'\(k)' not found."
        case .keychainFailed(let code): return "Keychain operation failed (\(code))."
        case .invalidName(let msg): return msg
        }
    }
}

struct LocalStore: Codable {
    var version: Int
    var projects: [LocalProject]
    var secrets: [LocalSecretRecord]
    var tags: [LocalTag]

    static func bootstrap() -> LocalStore {
        let envs = KeychainSecretStore.defaultEnvironments.map {
            LocalEnvironment(slug: $0,
                             name: KeychainSecretStore.defaultEnvironmentNames[$0] ?? $0.capitalized)
        }
        let project = LocalProject(
            id: KeychainSecretStore.localProjectId,
            name: "Local",
            environments: envs
        )
        return LocalStore(version: 1, projects: [project], secrets: [], tags: [])
    }
}

struct LocalProject: Codable {
    var id: String
    var name: String
    var environments: [LocalEnvironment]
}

struct LocalEnvironment: Codable {
    var slug: String
    var name: String
}

struct LocalSecretRecord: Codable {
    var id: String
    var projectId: String
    var environment: String
    var secretPath: String
    var key: String
    var value: String
    var comment: String?
    var tagIds: [String]
    var secretMetadata: [SecretMetadataEntry]?
    var createdAt: String
    var updatedAt: String

    func matches(projectId: String, environment: String, path: String) -> Bool {
        self.projectId == projectId
            && self.environment == environment
            && self.secretPath == path
    }

    func toSecretItem() -> SecretItem {
        SecretItem(
            id: id, key: key, value: value, type: nil, comment: comment,
            version: 1, tags: nil,
            secretMetadata: secretMetadata,
            createdAt: createdAt, updatedAt: updatedAt,
            environment: environment
        )
    }

    static func buildMetadata(expiryDate: Date?, serviceURL: String?)
        -> [SecretMetadataEntry]?
    {
        var out: [SecretMetadataEntry] = []
        if let date = expiryDate {
            out.append(SecretMetadataEntry(
                key: SecretMetadataKey.expiryDate,
                value: SecretMetadataDateFormatter.string(from: date)
            ))
        }
        if let url = serviceURL?.trimmingCharacters(in: .whitespacesAndNewlines),
           !url.isEmpty {
            out.append(SecretMetadataEntry(
                key: SecretMetadataKey.serviceUrl, value: url
            ))
        }
        return out.isEmpty ? nil : out
    }
}

struct LocalTag: Codable {
    var id: String
    var projectId: String
    var slug: String
    var name: String?
    var color: String?

    func toInfisical() -> InfisicalTag {
        InfisicalTag(id: id, name: name, slug: slug, color: color)
    }

    func toSecretTag() -> SecretTag {
        SecretTag(id: id, slug: slug, name: name, color: color)
    }
}
