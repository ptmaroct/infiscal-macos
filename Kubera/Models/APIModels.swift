import Foundation

struct InfisicalOrg: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let slug: String?
}

struct InfisicalProject: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let slug: String?
    let environments: [InfisicalEnvironment]
}

struct InfisicalEnvironment: Codable, Identifiable, Hashable {
    let name: String
    let slug: String

    var id: String { slug }
}

struct OrgsResponse: Codable {
    let organizations: [InfisicalOrg]
}

struct WorkspacesResponse: Codable {
    let workspaces: [InfisicalProject]
}

struct InfisicalTag: Codable, Identifiable, Hashable {
    let id: String
    let name: String?
    let slug: String
    let color: String?

    /// Display name: use name if available, otherwise slug
    var displayName: String { name ?? slug }
}

struct TagsResponse: Codable {
    let workspaceTags: [InfisicalTag]
}

struct SecretsListResponse: Codable {
    let secrets: [SecretItem]
}
