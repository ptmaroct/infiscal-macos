import Foundation
import KuberaCore

/// Shared helpers used across kubera subcommands.
enum Helpers {

    /// Load config or fail with a friendly error pointing the user at `kubera config set`.
    static func requireConfig() throws -> AppConfiguration {
        guard let cfg = AppConfiguration.load() else {
            throw ValidationError(
                "No Kubera config found. Run 'kubera config set --project <id>' or open the macOS app to configure."
            )
        }
        return cfg
    }

    /// True when stdout is connected to an interactive terminal.
    static var isTTY: Bool {
        isatty(fileno(stdout)) != 0
    }

    /// Print a line to stderr.
    static func warn(_ message: String) {
        FileHandle.standardError.write(Data("\(message)\n".utf8))
    }

    /// Print structured JSON to stdout.
    static func emitJSON<T: Encodable>(_ value: T) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(value)
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }

    /// Pipe stdin/stdout/stderr into a child process and return its exit code.
    @discardableResult
    static func runInherit(_ path: String, arguments: [String]) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardInput = FileHandle.standardInput
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }

    /// Fetch secrets honoring the all-environments sentinel (`*`).
    /// Routes through the active `SecretStore` so both Infisical and the local
    /// backend work transparently. Returns secrets with `environment` populated.
    static func fetchSecrets(
        config: AppConfiguration,
        envOverride: String? = nil,
        pathOverride: String? = nil
    ) async throws -> [SecretItem] {
        let effectiveEnv = envOverride ?? config.environment
        let effectivePath = pathOverride ?? config.secretPath
        let store = activeStore(config)

        if effectiveEnv != AppConfiguration.allEnvironmentsSentinel {
            let items = try await store.listSecrets(
                environment: effectiveEnv,
                projectId: config.projectId,
                secretPath: effectivePath
            )
            return items.map { var c = $0; c.environment = effectiveEnv; return c }
        }

        // All-envs fan-out: resolve env slugs from the backend's project list.
        let projects = try await store.listProjects()
        guard let project = projects.first(where: { $0.id == config.projectId }) else {
            throw ValidationError("Configured project \(config.projectId) not found.")
        }
        let envSlugs = project.environments.map(\.slug)

        return try await withThrowingTaskGroup(of: (Int, [SecretItem]).self) { group in
            for (idx, slug) in envSlugs.enumerated() {
                group.addTask {
                    let items = try await store.listSecrets(
                        environment: slug,
                        projectId: config.projectId,
                        secretPath: effectivePath
                    )
                    let tagged = items.map { var c = $0; c.environment = slug; return c }
                    return (idx, tagged)
                }
            }
            var collected: [(Int, [SecretItem])] = []
            for try await result in group { collected.append(result) }
            collected.sort { $0.0 < $1.0 }
            return collected.flatMap { $0.1 }
        }
    }

    /// Resolve the `infisical` CLI path, mirroring InfisicalCLIService logic for shell-outs.
    static func infisicalPath() -> String? {
        let candidates = [
            "/opt/homebrew/bin/infisical",
            "/usr/local/bin/infisical",
            "/usr/bin/infisical",
        ]
        for path in candidates where FileManager.default.fileExists(atPath: path) {
            return path
        }
        return nil
    }
}

extension Helpers {
    /// Build the active SecretStore for the loaded config. Used by commands that
    /// must work for either backend (export/import, future read/write paths).
    static func activeStore(_ config: AppConfiguration) -> SecretStore {
        SecretStoreFactory.make(for: config)
    }

    /// Read a password from /dev/tty without echoing. Falls back to readLine() on
    /// stdin if /dev/tty is unavailable (e.g. tests).
    static func readPassword(prompt: String) -> String? {
        FileHandle.standardError.write(Data(prompt.utf8))
        if let buf = getpass("") {
            return String(cString: buf)
        }
        return readLine(strippingNewline: true)
    }
}

/// Lightweight validation error so subcommands can fail with non-zero exit + clean message.
struct ValidationError: Error, CustomStringConvertible {
    let description: String
    init(_ message: String) { self.description = message }
}
