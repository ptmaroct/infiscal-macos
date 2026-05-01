import Foundation

/// Tag attached to a secret
public struct SecretTag: Codable, Identifiable, Hashable {
    public let id: String
    public let slug: String
    public let name: String?
    public let color: String?

    public var displayName: String { name ?? slug }

    public init(id: String, slug: String, name: String?, color: String?) {
        self.id = id
        self.slug = slug
        self.name = name
        self.color = color
    }
}

/// Custom metadata key/value entry on an Infisical secret.
/// Sent and received as `secretMetadata: [{ key, value }]` on /api/v3/secrets/raw.
public struct SecretMetadataEntry: Codable, Hashable {
    public let key: String
    public let value: String

    public init(key: String, value: String) {
        self.key = key
        self.value = value
    }
}

/// Well-known metadata keys used by Kubera.
public enum SecretMetadataKey {
    public static let expiryDate = "expiryDate"  // ISO-8601 date: YYYY-MM-DD
    public static let serviceUrl = "serviceUrl"  // absolute URL of the issuing service's keys page
}

/// Represents a single secret from Infisical REST API.
/// GET /api/v3/secrets/raw returns these fields (among others).
public struct SecretItem: Codable, Identifiable, Hashable {
    public let id: String
    public let key: String
    public var value: String
    public let type: String?
    public let comment: String?
    public let version: Int?
    public let tags: [SecretTag]?
    public let secretMetadata: [SecretMetadataEntry]?
    public let createdAt: String?
    public let updatedAt: String?

    /// Environment slug this secret was fetched from. Populated client-side after
    /// fetch (not part of the API response) so the same key can appear in multiple
    /// envs when "All Environments" mode is active.
    public var environment: String?

    /// Project context stamped client-side after fetch. Infisical secret payloads
    /// do not include this, but Kubera needs it when browsing all projects.
    public var projectId: String?
    public var projectName: String?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case key = "secretKey"
        case value = "secretValue"
        case type
        case comment = "secretComment"
        // Client-stamped context round-trips through the local cache so badges
        // and filters render instantly on cold start.
        case version, tags, secretMetadata, createdAt, updatedAt, environment, projectId, projectName
    }

    public init(
        id: String = UUID().uuidString,
        key: String,
        value: String,
        type: String? = nil,
        comment: String? = nil,
        version: Int? = nil,
        tags: [SecretTag]? = nil,
        secretMetadata: [SecretMetadataEntry]? = nil,
        createdAt: String? = nil,
        updatedAt: String? = nil,
        environment: String? = nil,
        projectId: String? = nil,
        projectName: String? = nil
    ) {
        self.id = id
        self.key = key
        self.value = value
        self.type = type
        self.comment = comment
        self.version = version
        self.tags = tags
        self.secretMetadata = secretMetadata
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.environment = environment
        self.projectId = projectId
        self.projectName = projectName
    }

    // MARK: - Metadata helpers

    private func metadataValue(forKey key: String) -> String? {
        secretMetadata?.first(where: { $0.key == key })?.value
    }

    /// Parsed expiry date (calendar day in current TZ) — nil if absent or unparseable.
    public var expiryDate: Date? {
        guard let raw = metadataValue(forKey: SecretMetadataKey.expiryDate),
              !raw.isEmpty else { return nil }
        return SecretMetadataDateFormatter.shared.date(from: raw)
    }

    /// Service-keys URL — nil if absent or unparseable.
    public var serviceURL: URL? {
        guard let raw = metadataValue(forKey: SecretMetadataKey.serviceUrl),
              !raw.isEmpty else { return nil }
        return URL(string: raw)
    }
}

/// Encode/decode `expiryDate` metadata values as ISO-8601 calendar days.
public enum SecretMetadataDateFormatter {
    public static let shared: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    public static func string(from date: Date) -> String { shared.string(from: date) }
    public static func date(from string: String) -> Date? { shared.date(from: string) }
}

/// Build the metadata array for a create/update API call.
/// Returns array form expected by Infisical: `[{ "key": ..., "value": ... }]`.
/// nil/empty inputs are omitted; if all inputs are nil/empty, returns an empty array
/// (caller should drop the field entirely in that case to avoid clearing existing metadata).
public func buildSecretMetadataPayload(expiryDate: Date?, serviceURL: String?) -> [[String: String]] {
    var out: [[String: String]] = []
    if let date = expiryDate {
        out.append(["key": SecretMetadataKey.expiryDate,
                    "value": SecretMetadataDateFormatter.string(from: date)])
    }
    if let url = serviceURL?.trimmingCharacters(in: .whitespacesAndNewlines), !url.isEmpty {
        out.append(["key": SecretMetadataKey.serviceUrl, "value": url])
    }
    return out
}
