import Foundation

/// Backend-agnostic interface for secret CRUD. Implemented by `InfisicalSecretStore`
/// (talks to Infisical REST API) and `KeychainSecretStore` (local Keychain + encrypted
/// metadata file). Adding a new backend means writing a new conformer; nothing else
/// in the app needs to know which one is active.
///
/// Concepts kept generic:
///   - `projectId`: opaque namespace identifier. For local storage there is one
///     synthetic project (`KeychainSecretStore.localProjectId`).
///   - `environment`: env slug inside a project (e.g. "dev", "prod"). Local storage
///     ships a default set the user can rename.
///   - `secretPath`: virtual folder path inside an env (e.g. "/", "/api").
public protocol SecretStore: Sendable {
    /// Stable backend identifier. Persisted in `AppConfiguration.storeBackend`.
    var id: String { get }

    /// Human-readable name shown in Settings.
    var displayName: String { get }

    /// True if the backend is ready to serve requests (e.g. logged in, keys present).
    func isReady() async -> Bool

    func listSecrets(environment: String, projectId: String, secretPath: String) async throws -> [SecretItem]

    func createSecret(
        name: String,
        value: String,
        comment: String,
        tagIds: [String],
        expiryDate: Date?,
        serviceURL: String?,
        environment: String,
        projectId: String,
        secretPath: String
    ) async throws

    func updateSecret(
        name: String,
        value: String,
        comment: String,
        tagIds: [String],
        tagsExplicit: Bool,
        expiryDate: Date?,
        serviceURL: String?,
        metadataExplicit: Bool,
        environment: String,
        projectId: String,
        secretPath: String
    ) async throws

    func deleteSecret(
        name: String,
        environment: String,
        projectId: String,
        secretPath: String
    ) async throws

    func listProjects() async throws -> [InfisicalProject]
    func listTags(projectId: String) async throws -> [InfisicalTag]
    func createTag(name: String, color: String, projectId: String) async throws -> InfisicalTag

    /// Create a new project. For Infisical this throws — projects are created in
    /// the dashboard. Local backend creates a project locally.
    func createProject(name: String) async throws -> InfisicalProject

    /// Create a new environment in an existing project. Both backends support this.
    func createEnvironment(name: String, slug: String, projectId: String) async throws -> InfisicalEnvironment
}

public enum SecretStoreFeatureError: LocalizedError {
    case unsupportedByBackend(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedByBackend(let msg): return msg
        }
    }
}

public enum SecretStoreBackendID {
    public static let infisical = "infisical"
    public static let local = "local"
}

/// Adapter that exposes the existing static `InfisicalCLIService` API through
/// the `SecretStore` protocol. Behaviour is unchanged — every method forwards
/// to the static implementation. The `baseURL` is captured at construction time
/// so call sites don't have to thread it through every call.
public struct InfisicalSecretStore: SecretStore {
    public let id = SecretStoreBackendID.infisical
    public let displayName = "Infisical"

    public let baseURL: String

    public init(baseURL: String = AppConfiguration.defaultBaseURL) {
        self.baseURL = baseURL
    }

    public func isReady() async -> Bool {
        guard InfisicalCLIService.isInstalled() else { return false }
        return await InfisicalCLIService.isLoggedIn()
    }

    public func listSecrets(environment: String, projectId: String, secretPath: String) async throws -> [SecretItem] {
        try await InfisicalCLIService.listSecretsViaAPI(
            environment: environment,
            projectId: projectId,
            secretPath: secretPath,
            baseURL: baseURL
        )
    }

    public func createSecret(
        name: String,
        value: String,
        comment: String,
        tagIds: [String],
        expiryDate: Date?,
        serviceURL: String?,
        environment: String,
        projectId: String,
        secretPath: String
    ) async throws {
        try await InfisicalCLIService.createSecretViaAPI(
            name: name,
            value: value,
            comment: comment,
            tagIds: tagIds,
            expiryDate: expiryDate,
            serviceURL: serviceURL,
            environment: environment,
            projectId: projectId,
            secretPath: secretPath,
            baseURL: baseURL
        )
    }

    public func updateSecret(
        name: String,
        value: String,
        comment: String,
        tagIds: [String],
        tagsExplicit: Bool,
        expiryDate: Date?,
        serviceURL: String?,
        metadataExplicit: Bool,
        environment: String,
        projectId: String,
        secretPath: String
    ) async throws {
        try await InfisicalCLIService.updateSecret(
            name: name,
            value: value,
            comment: comment,
            tagIds: tagIds,
            tagsExplicit: tagsExplicit,
            expiryDate: expiryDate,
            serviceURL: serviceURL,
            metadataExplicit: metadataExplicit,
            environment: environment,
            projectId: projectId,
            secretPath: secretPath,
            baseURL: baseURL
        )
    }

    public func deleteSecret(
        name: String,
        environment: String,
        projectId: String,
        secretPath: String
    ) async throws {
        try await InfisicalCLIService.deleteSecret(
            name: name,
            environment: environment,
            projectId: projectId,
            secretPath: secretPath,
            baseURL: baseURL
        )
    }

    public func listProjects() async throws -> [InfisicalProject] {
        let orgs = try await InfisicalCLIService.fetchOrganizations(baseURL: baseURL)
        var all: [InfisicalProject] = []
        for org in orgs {
            let projects = try await InfisicalCLIService.fetchProjects(orgId: org.id, baseURL: baseURL)
            all.append(contentsOf: projects)
        }
        return all
    }

    public func listTags(projectId: String) async throws -> [InfisicalTag] {
        try await InfisicalCLIService.fetchTags(projectId: projectId, baseURL: baseURL)
    }

    public func createTag(name: String, color: String, projectId: String) async throws -> InfisicalTag {
        try await InfisicalCLIService.createTag(name: name, projectId: projectId, color: color, baseURL: baseURL)
    }

    public func createProject(name: String) async throws -> InfisicalProject {
        throw SecretStoreFeatureError.unsupportedByBackend(
            "Create projects in the Infisical dashboard, then refresh."
        )
    }

    public func createEnvironment(name: String, slug: String,
                                  projectId: String) async throws -> InfisicalEnvironment {
        try await InfisicalCLIService.createEnvironment(
            name: name, slug: slug, projectId: projectId, baseURL: baseURL
        )
    }
}
