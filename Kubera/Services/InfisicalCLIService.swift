import Foundation

enum CLIError: LocalizedError {
    case notInstalled
    case notLoggedIn
    case executionFailed(String)
    case parseError(String)

    var errorDescription: String? {
        switch self {
        case .notInstalled:
            return "Infisical CLI is not installed. Install it with: brew install infisical"
        case .notLoggedIn:
            return "Not logged in. Run 'infisical login' in your terminal first."
        case .executionFailed(let msg):
            return "CLI error: \(msg)"
        case .parseError(let msg):
            return "Failed to parse CLI output: \(msg)"
        }
    }
}

struct InfisicalCLIService {

    /// Find the infisical binary path
    private static func cliPath() -> String? {
        let knownPaths = [
            "/opt/homebrew/bin/infisical",
            "/usr/local/bin/infisical",
            "/usr/bin/infisical"
        ]
        for path in knownPaths {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }
        // Try `which`
        if let result = try? runShell("/bin/zsh", arguments: ["-c", "which infisical"]),
           !result.isEmpty {
            return result.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    /// Check if CLI is installed
    static func isInstalled() -> Bool {
        cliPath() != nil
    }

    /// Check if user is logged in by running `infisical user get token`
    static func isLoggedIn() async -> Bool {
        guard let cli = cliPath() else { return false }
        do {
            let output = try runShell(cli, arguments: ["user", "get", "token"])
            // If we get a token back, user is logged in
            return output.contains("Token:")
        } catch {
            return false
        }
    }

    /// List all secrets as JSON using `infisical export`
    static func listSecrets(environment: String, projectId: String, secretPath: String = "/") async throws -> [SecretItem] {
        guard let cli = cliPath() else { throw CLIError.notInstalled }

        var args = ["export", "--format=json", "--silent"]
        args.append("--env=\(environment)")
        args.append("--projectId=\(projectId)")
        if secretPath != "/" {
            args.append("--path=\(secretPath)")
        }

        let output: String
        do {
            output = try runShell(cli, arguments: args)
        } catch {
            throw CLIError.executionFailed(error.localizedDescription)
        }

        guard !output.isEmpty else {
            return []
        }

        // Parse JSON array
        guard let data = output.data(using: .utf8) else {
            throw CLIError.parseError("Invalid UTF-8 output")
        }

        do {
            let secrets = try JSONDecoder().decode([SecretItem].self, from: data)
            return secrets
        } catch {
            throw CLIError.parseError(error.localizedDescription)
        }
    }

    /// Create a new secret using `infisical secrets set`
    static func createSecret(key: String, value: String, environment: String, projectId: String, secretPath: String = "/") async throws {
        guard let cli = cliPath() else { throw CLIError.notInstalled }

        var args = ["secrets", "set", "\(key)=\(value)"]
        args.append("--env=\(environment)")
        args.append("--projectId=\(projectId)")
        if secretPath != "/" {
            args.append("--path=\(secretPath)")
        }

        do {
            _ = try runShell(cli, arguments: args)
        } catch {
            throw CLIError.executionFailed(error.localizedDescription)
        }
    }

    /// Get the logged-in user's access token from CLI
    static func getToken() -> String? {
        guard let cli = cliPath() else { return nil }
        guard let output = try? runShell(cli, arguments: ["user", "get", "token"]) else { return nil }
        // Parse "Token: <jwt>" from output
        for line in output.components(separatedBy: "\n") {
            if line.hasPrefix("Token:") {
                return line.replacingOccurrences(of: "Token:", with: "").trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    /// Fetch organizations for the logged-in user via API
    static func fetchOrganizations(baseURL: String = "https://app.infisical.com") async throws -> [InfisicalOrg] {
        guard let token = getToken() else { throw CLIError.notLoggedIn }
        let url = URL(string: "\(baseURL)/api/v2/users/me/organizations")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(OrgsResponse.self, from: data)
        return response.organizations
    }

    /// Fetch workspaces (projects) for an organization via API
    static func fetchProjects(orgId: String, baseURL: String = "https://app.infisical.com") async throws -> [InfisicalProject] {
        guard let token = getToken() else { throw CLIError.notLoggedIn }
        let url = URL(string: "\(baseURL)/api/v2/organizations/\(orgId)/workspaces")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(WorkspacesResponse.self, from: data)
        return response.workspaces
    }

    /// Fetch tags for a workspace (project) via API (v1 endpoint)
    static func fetchTags(projectId: String, baseURL: String = "https://app.infisical.com") async throws -> [InfisicalTag] {
        guard let token = getToken() else { throw CLIError.notLoggedIn }
        let url = URL(string: "\(baseURL)/api/v1/workspace/\(projectId)/tags")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode >= 400 {
            if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let message = errorJson["message"] as? String {
                throw CLIError.executionFailed(message)
            }
            throw CLIError.executionFailed("Failed to fetch tags")
        }

        let decoded = try JSONDecoder().decode(TagsResponse.self, from: data)
        return decoded.workspaceTags
    }

    /// Create a new tag in a workspace via API (v1 endpoint)
    static func createTag(name: String, projectId: String, color: String = "#F5A524", baseURL: String = "https://app.infisical.com") async throws -> InfisicalTag {
        guard let token = getToken() else { throw CLIError.notLoggedIn }
        let url = URL(string: "\(baseURL)/api/v1/workspace/\(projectId)/tags")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10

        let slug = name.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "[^a-z0-9\\-]", with: "", options: .regularExpression)

        let body: [String: Any] = [
            "slug": slug,
            "color": color
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode >= 400 {
            if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let message = errorJson["message"] as? String {
                throw CLIError.executionFailed(message)
            }
            throw CLIError.executionFailed("Failed to create tag")
        }

        // Parse the created tag from response
        struct CreateTagResponse: Codable {
            let workspaceTag: InfisicalTag
        }
        let tagResponse = try JSONDecoder().decode(CreateTagResponse.self, from: data)
        return tagResponse.workspaceTag
    }

    /// List all secrets via Infisical REST API (returns rich metadata: version, tags, timestamps)
    static func listSecretsViaAPI(
        environment: String,
        projectId: String,
        secretPath: String = "/",
        baseURL: String = "https://app.infisical.com"
    ) async throws -> [SecretItem] {
        guard let token = getToken() else { throw CLIError.notLoggedIn }

        var components = URLComponents(string: "\(baseURL)/api/v3/secrets/raw")!
        components.queryItems = [
            URLQueryItem(name: "workspaceId", value: projectId),
            URLQueryItem(name: "environment", value: environment),
            URLQueryItem(name: "secretPath", value: secretPath)
        ]

        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode >= 400 {
            if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let message = errorJson["message"] as? String {
                throw CLIError.executionFailed(message)
            }
            throw CLIError.executionFailed("Failed to fetch secrets")
        }

        let decoded = try JSONDecoder().decode(SecretsListResponse.self, from: data)
        return decoded.secrets
    }

    /// Update an existing secret via Infisical REST API.
    ///
    /// `expiryDate` and `serviceURL` are written into Infisical's native `secretMetadata`
    /// array. Pass `metadataExplicit: true` (default) to overwrite metadata even when
    /// both are nil — that lets callers clear the values. Pass `false` to leave
    /// existing metadata untouched.
    static func updateSecret(
        name: String,
        value: String,
        comment: String = "",
        tagIds: [String] = [],
        expiryDate: Date? = nil,
        serviceURL: String? = nil,
        metadataExplicit: Bool = true,
        environment: String,
        projectId: String,
        secretPath: String = "/",
        baseURL: String = "https://app.infisical.com"
    ) async throws {
        guard let token = getToken() else { throw CLIError.notLoggedIn }
        let encodedName = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
        let url = URL(string: "\(baseURL)/api/v3/secrets/raw/\(encodedName)")!
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15

        var body: [String: Any] = [
            "workspaceId": projectId,
            "environment": environment,
            "secretPath": secretPath,
            "secretValue": value
        ]
        if !comment.isEmpty { body["secretComment"] = comment }
        if !tagIds.isEmpty { body["tagIds"] = tagIds }
        if metadataExplicit {
            body["secretMetadata"] = buildSecretMetadataPayload(
                expiryDate: expiryDate, serviceURL: serviceURL
            )
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode >= 400 {
            if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let message = errorJson["message"] as? String {
                throw CLIError.executionFailed(message)
            }
            throw CLIError.executionFailed("Failed to update secret")
        }
    }

    /// Delete a secret via Infisical REST API
    static func deleteSecret(
        name: String,
        environment: String,
        projectId: String,
        secretPath: String = "/",
        baseURL: String = "https://app.infisical.com"
    ) async throws {
        guard let token = getToken() else { throw CLIError.notLoggedIn }
        let encodedName = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
        let url = URL(string: "\(baseURL)/api/v3/secrets/raw/\(encodedName)")!
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15

        let body: [String: Any] = [
            "workspaceId": projectId,
            "environment": environment,
            "secretPath": secretPath
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode >= 400 {
            if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let message = errorJson["message"] as? String {
                throw CLIError.executionFailed(message)
            }
            throw CLIError.executionFailed("Failed to delete secret")
        }
    }

    /// Create a new secret via Infisical REST API (supports comment, tags, and metadata).
    static func createSecretViaAPI(
        name: String,
        value: String,
        comment: String = "",
        tagIds: [String] = [],
        expiryDate: Date? = nil,
        serviceURL: String? = nil,
        environment: String,
        projectId: String,
        secretPath: String = "/",
        baseURL: String = "https://app.infisical.com"
    ) async throws {
        guard let token = getToken() else { throw CLIError.notLoggedIn }
        let encodedName = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
        let url = URL(string: "\(baseURL)/api/v3/secrets/raw/\(encodedName)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15

        var body: [String: Any] = [
            "workspaceId": projectId,
            "environment": environment,
            "secretPath": secretPath,
            "secretValue": value,
            "type": "shared"
        ]
        if !comment.isEmpty { body["secretComment"] = comment }
        if !tagIds.isEmpty { body["tagIds"] = tagIds }
        let metadata = buildSecretMetadataPayload(expiryDate: expiryDate, serviceURL: serviceURL)
        if !metadata.isEmpty { body["secretMetadata"] = metadata }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode >= 400 {
            // Try to parse error message from response
            if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let message = errorJson["message"] as? String {
                throw CLIError.executionFailed(message)
            }
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw CLIError.executionFailed(errorBody)
        }
    }

    // MARK: - Shell Execution

    private static func runShell(_ path: String, arguments: [String]) throws -> String {
        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe

        // Inherit PATH so CLI can find its dependencies
        var env = ProcessInfo.processInfo.environment
        if env["PATH"] == nil {
            env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        }
        process.environment = env

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""

        if process.terminationStatus != 0 {
            throw CLIError.executionFailed(output.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
