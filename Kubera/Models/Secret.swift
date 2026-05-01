import Foundation

/// Tag attached to a secret
struct SecretTag: Codable, Identifiable, Hashable {
    let id: String
    let slug: String
    let name: String?
    let color: String?

    var displayName: String { name ?? slug }
}

/// Custom metadata key/value entry on an Infisical secret.
/// Sent and received as `secretMetadata: [{ key, value }]` on /api/v3/secrets/raw.
struct SecretMetadataEntry: Codable, Hashable {
    let key: String
    let value: String
}

/// Well-known metadata keys used by Kubera.
enum SecretMetadataKey {
    static let expiryDate = "expiryDate"  // ISO-8601 date: YYYY-MM-DD
    static let serviceUrl = "serviceUrl"  // absolute URL of the issuing service's keys page
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
    let secretMetadata: [SecretMetadataEntry]?
    let createdAt: String?
    let updatedAt: String?

    /// Environment slug this secret was fetched from. Populated client-side after
    /// fetch (not part of the API response) so the same key can appear in multiple
    /// envs when "All Environments" mode is active.
    var environment: String?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case key = "secretKey"
        case value = "secretValue"
        case type
        case comment = "secretComment"
        case version, tags, secretMetadata, createdAt, updatedAt
    }

    init(
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
        environment: String? = nil
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
    }

    // MARK: - Metadata helpers

    private func metadataValue(forKey key: String) -> String? {
        secretMetadata?.first(where: { $0.key == key })?.value
    }

    /// Parsed expiry date (calendar day in current TZ) — nil if absent or unparseable.
    var expiryDate: Date? {
        guard let raw = metadataValue(forKey: SecretMetadataKey.expiryDate),
              !raw.isEmpty else { return nil }
        return SecretMetadataDateFormatter.shared.date(from: raw)
    }

    /// Service-keys URL — nil if absent or unparseable.
    var serviceURL: URL? {
        guard let raw = metadataValue(forKey: SecretMetadataKey.serviceUrl),
              !raw.isEmpty else { return nil }
        return URL(string: raw)
    }
}

/// Encode/decode `expiryDate` metadata values as ISO-8601 calendar days.
enum SecretMetadataDateFormatter {
    static let shared: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func string(from date: Date) -> String { shared.string(from: date) }
    static func date(from string: String) -> Date? { shared.date(from: string) }
}

/// Build the metadata array for a create/update API call.
/// Returns array form expected by Infisical: `[{ "key": ..., "value": ... }]`.
/// nil/empty inputs are omitted; if all inputs are nil/empty, returns an empty array
/// (caller should drop the field entirely in that case to avoid clearing existing metadata).
func buildSecretMetadataPayload(expiryDate: Date?, serviceURL: String?) -> [[String: String]] {
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
