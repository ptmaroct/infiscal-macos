import Foundation

/// Tag attached to a secret
struct SecretTag: Codable, Identifiable, Hashable {
    let id: String
    let slug: String
    let name: String?
    let color: String?

    var displayName: String { name ?? slug }
}

/// Represents a single secret from Infisical REST API.
/// GET /api/v3/secrets/raw returns these fields (among others).
struct SecretItem: Codable, Identifiable, Hashable {
    let id: String
    let key: String
    let value: String
    let type: String?
    let comment: String?
    let version: Int?
    let tags: [SecretTag]?
    let createdAt: String?
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case key = "secretKey"
        case value = "secretValue"
        case type
        case comment = "secretComment"
        case version, tags, createdAt, updatedAt
    }

    init(
        id: String = UUID().uuidString,
        key: String,
        value: String,
        type: String? = nil,
        comment: String? = nil,
        version: Int? = nil,
        tags: [SecretTag]? = nil,
        createdAt: String? = nil,
        updatedAt: String? = nil
    ) {
        self.id = id
        self.key = key
        self.value = value
        self.type = type
        self.comment = comment
        self.version = version
        self.tags = tags
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
