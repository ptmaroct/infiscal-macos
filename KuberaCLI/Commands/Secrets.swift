import ArgumentParser
import Foundation
import KuberaCore

// MARK: - List

struct List: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ls",
        abstract: "List secret keys (and optionally values) for the configured project/environment."
    )

    @Option(name: .long, help: "Override environment slug.") var env: String?
    @Option(name: .long, help: "Override secret path.") var path: String?
    @Option(name: [.short, .long], help: "Filter to secrets carrying this tag slug. Repeat for OR-match.")
    var tag: [String] = []
    @Flag(name: .long, help: "Include values in the output. Off by default to avoid leaking secrets.")
    var values: Bool = false
    @Flag(help: "Emit JSON.") var json: Bool = false

    func run() async throws {
        let cfg = try Helpers.requireConfig()
        var secrets = try await Helpers.fetchSecrets(
            config: cfg, envOverride: env, pathOverride: path
        )
        if !tag.isEmpty {
            let wanted = Swift.Set(tag)
            secrets = secrets.filter { secret in
                guard let tags = secret.tags else { return false }
                return tags.contains { wanted.contains($0.slug) }
            }
        }
        if json {
            if values {
                try Helpers.emitJSON(secrets)
            } else {
                try Helpers.emitJSON(secrets.map(\.key))
            }
            return
        }
        for s in secrets {
            let envTag = (cfg.isAllEnvironments && env == nil) ? "  [\(s.environment ?? "?")]" : ""
            if values {
                print("\(s.key)=\(s.value)\(envTag)")
            } else {
                print("\(s.key)\(envTag)")
            }
        }
    }
}

// MARK: - Info

struct Info: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Show full metadata for a secret: version, comment, tags, expiry, service URL."
    )

    @Argument(help: "Secret key.") var key: String
    @Option(name: .long, help: "Override environment slug.") var env: String?
    @Flag(help: "Emit JSON.") var json: Bool = false

    func run() async throws {
        let cfg = try Helpers.requireConfig()
        let secrets = try await Helpers.fetchSecrets(config: cfg, envOverride: env)
        guard let secret = secrets.first(where: { $0.key == key }) else {
            throw ValidationError("Secret '\(key)' not found.")
        }
        if json { try Helpers.emitJSON(secret); return }
        print("key:        \(secret.key)")
        print("env:        \(secret.environment ?? cfg.environment)")
        print("version:    \(secret.version.map(String.init) ?? "-")")
        print("comment:    \(secret.comment ?? "-")")
        print("tags:       \(secret.tags?.map(\.slug).joined(separator: ", ") ?? "-")")
        if let expiry = secret.expiryDate {
            print("expires:    \(SecretMetadataDateFormatter.string(from: expiry))")
        }
        if let url = secret.serviceURL {
            print("service:    \(url.absoluteString)")
        }
        print("createdAt:  \(secret.createdAt ?? "-")")
        print("updatedAt:  \(secret.updatedAt ?? "-")")
    }
}

// MARK: - Get

struct Get: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Print a single secret value to stdout.")

    @Argument(help: "Secret key.") var key: String
    @Option(name: .long, help: "Override environment slug.") var env: String?
    @Option(name: .long, help: "Override secret path.") var path: String?

    func run() async throws {
        let cfg = try Helpers.requireConfig()
        let secrets = try await Helpers.fetchSecrets(
            config: cfg, envOverride: env, pathOverride: path
        )
        guard let secret = secrets.first(where: { $0.key == key }) else {
            throw ValidationError("Secret '\(key)' not found in \(env ?? cfg.environment).")
        }
        // Print without trailing newline if piped, with newline on TTY for readability.
        if Helpers.isTTY {
            print(secret.value)
        } else {
            FileHandle.standardOutput.write(Data(secret.value.utf8))
        }
    }
}

// MARK: - Copy

struct Copy: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Copy a secret value to the clipboard via pbcopy.")

    @Argument(help: "Secret key.") var key: String
    @Option(name: .long, help: "Override environment slug.") var env: String?

    func run() async throws {
        let cfg = try Helpers.requireConfig()
        let secrets = try await Helpers.fetchSecrets(config: cfg, envOverride: env)
        guard let secret = secrets.first(where: { $0.key == key }) else {
            throw ValidationError("Secret '\(key)' not found.")
        }

        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pbcopy")
        process.standardInput = pipe
        try process.run()
        pipe.fileHandleForWriting.write(Data(secret.value.utf8))
        try pipe.fileHandleForWriting.close()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            throw ValidationError("pbcopy exited \(process.terminationStatus)")
        }
        Helpers.warn("copied \(key) to clipboard")
    }
}

// MARK: - Set

struct Set: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Create or update a secret (upsert).")

    @Argument(help: "Secret key.") var key: String
    @Argument(help: "Secret value. Pass '-' to read from stdin.") var value: String

    @Option(name: .long, help: "Override environment slug.") var env: String?
    @Option(name: .long, help: "Override secret path.") var path: String?
    @Option(name: .long, help: "Optional comment to attach.") var comment: String = ""
    @Option(name: [.short, .long], help: "Tag ID(s) to attach. Repeat for multiple.")
    var tag: [String] = []

    func run() async throws {
        let cfg = try Helpers.requireConfig()
        let environment = env ?? cfg.environment
        guard environment != AppConfiguration.allEnvironmentsSentinel else {
            throw ValidationError("Cannot write to all environments at once. Pass --env <slug>.")
        }
        let secretPath = path ?? cfg.secretPath
        let resolvedValue: String
        if value == "-" {
            let data = FileHandle.standardInput.readDataToEndOfFile()
            resolvedValue = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        } else {
            resolvedValue = value
        }

        // Detect existing key → update vs create.
        let existing = try await InfisicalCLIService.listSecretsViaAPI(
            environment: environment,
            projectId: cfg.projectId,
            secretPath: secretPath,
            baseURL: cfg.baseURL
        )
        if existing.contains(where: { $0.key == key }) {
            try await InfisicalCLIService.updateSecret(
                name: key, value: resolvedValue, comment: comment, tagIds: tag,
                environment: environment, projectId: cfg.projectId,
                secretPath: secretPath, baseURL: cfg.baseURL
            )
            Helpers.warn("updated \(key)")
        } else {
            try await InfisicalCLIService.createSecretViaAPI(
                name: key, value: resolvedValue, comment: comment, tagIds: tag,
                environment: environment, projectId: cfg.projectId,
                secretPath: secretPath, baseURL: cfg.baseURL
            )
            Helpers.warn("created \(key)")
        }
    }
}

// MARK: - Remove

struct Remove: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "rm",
        abstract: "Delete a secret."
    )

    @Argument(help: "Secret key.") var key: String
    @Option(name: .long, help: "Override environment slug.") var env: String?
    @Flag(name: [.short, .long], help: "Skip the confirmation prompt.")
    var force: Bool = false

    func run() async throws {
        let cfg = try Helpers.requireConfig()
        let environment = env ?? cfg.environment
        guard environment != AppConfiguration.allEnvironmentsSentinel else {
            throw ValidationError("Cannot delete from all environments at once. Pass --env <slug>.")
        }

        if !force {
            FileHandle.standardError.write(Data("Delete '\(key)' from \(environment)? [y/N] ".utf8))
            let line = readLine() ?? ""
            guard line.lowercased().hasPrefix("y") else {
                Helpers.warn("aborted")
                return
            }
        }

        try await InfisicalCLIService.deleteSecret(
            name: key,
            environment: environment,
            projectId: cfg.projectId,
            secretPath: cfg.secretPath,
            baseURL: cfg.baseURL
        )
        Helpers.warn("deleted \(key)")
    }
}

// MARK: - Export

struct Export: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Dump all secrets in dotenv, json, or shell format."
    )

    enum Format: String, ExpressibleByArgument {
        case dotenv, json, shell
    }

    @Option(name: .long, help: "Output format: dotenv|json|shell.") var format: Format = .dotenv
    @Option(name: .long, help: "Override environment slug.") var env: String?
    @Option(name: .long, help: "Override secret path.") var path: String?

    func run() async throws {
        let cfg = try Helpers.requireConfig()
        let secrets = try await Helpers.fetchSecrets(
            config: cfg, envOverride: env, pathOverride: path
        )
        switch format {
        case .dotenv:
            for s in secrets {
                print("\(s.key)=\(quoteDotenv(s.value))")
            }
        case .json:
            var dict: [String: String] = [:]
            for s in secrets { dict[s.key] = s.value }
            try Helpers.emitJSON(dict)
        case .shell:
            for s in secrets {
                print("export \(s.key)=\(quoteShell(s.value))")
            }
        }
    }

    private func quoteDotenv(_ value: String) -> String {
        if value.contains(where: { "\"\\\n#= ".contains($0) }) {
            let escaped = value
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            return "\"\(escaped)\""
        }
        return value
    }

    private func quoteShell(_ value: String) -> String {
        // Single-quote and escape embedded single quotes.
        let escaped = value.replacingOccurrences(of: "'", with: "'\\''")
        return "'\(escaped)'"
    }
}

// MARK: - Run

struct Run: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Inject secrets as env vars and exec a subcommand. Example: kubera run -- npm run dev"
    )

    @Option(name: .long, help: "Override environment slug.") var env: String?
    @Option(name: .long, help: "Override secret path.") var path: String?

    @Argument(parsing: .captureForPassthrough, help: "Command and arguments to execute.")
    var command: [String] = []

    func run() async throws {
        guard let exe = command.first, !exe.isEmpty else {
            throw ValidationError("Usage: kubera run -- <command> [args...]")
        }
        let cfg = try Helpers.requireConfig()
        let secrets = try await Helpers.fetchSecrets(
            config: cfg, envOverride: env, pathOverride: path
        )

        var environment = ProcessInfo.processInfo.environment
        for s in secrets { environment[s.key] = s.value }

        let resolved = resolveExecutable(exe)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: resolved)
        process.arguments = Array(command.dropFirst())
        process.environment = environment
        process.standardInput = FileHandle.standardInput
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            throw ExitCode(process.terminationStatus)
        }
    }

    private func resolveExecutable(_ name: String) -> String {
        if name.contains("/") { return name }
        let path = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin"
        for dir in path.split(separator: ":") {
            let candidate = "\(dir)/\(name)"
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return name
    }
}

// MARK: - Open

struct Open: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Open the Kubera macOS app (or its dashboard URL)."
    )

    @Flag(name: .long, help: "Open the Infisical dashboard URL for the configured project instead of the app.")
    var dashboard: Bool = false

    func run() async throws {
        if dashboard {
            guard let cfg = AppConfiguration.load() else {
                throw ValidationError("No config — can't compute dashboard URL.")
            }
            _ = try Helpers.runInherit("/usr/bin/open", arguments: [cfg.dashboardURL])
        } else {
            _ = try Helpers.runInherit("/usr/bin/open", arguments: ["-a", "Kubera"])
        }
    }
}
