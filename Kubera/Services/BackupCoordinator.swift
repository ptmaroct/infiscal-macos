import Foundation
import AppKit
import KuberaCore

/// Drives the encrypted backup/restore flows from the Settings UI.
///
/// Each operation is a single async call:
///   - `runBackup(viewModel:)` opens a save panel, prompts for a password twice,
///     gathers the visible secrets, writes a `.kubera` archive.
///   - `runRestore(viewModel:overwrite:)` opens an open panel, prompts for a
///     password once, decrypts, writes secrets back through the active backend
///     and reloads the menubar list.
///
/// Errors are surfaced through NSAlert so the user gets a clear message; the
/// caller only needs to know "did it succeed" via the returned `BackupResult`.
@MainActor
enum BackupCoordinator {
    enum BackupResult {
        case cancelled
        case success(count: Int, url: URL)
        case failed(String)
    }

    static func runBackup(viewModel: AppViewModel) async -> BackupResult {
        guard let config = AppConfiguration.load() else {
            return .failed("Configure Kubera first.")
        }

        let panel = NSSavePanel()
        panel.title = "Save Kubera Backup"
        panel.nameFieldStringValue = defaultBackupName()
        panel.allowedContentTypes = []
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else {
            return .cancelled
        }

        guard let pw = promptPassword(
            title: "Set Backup Password",
            message: "Choose a password to encrypt this archive. You will need it to restore."
        ) else { return .cancelled }
        guard let confirm = promptPassword(
            title: "Confirm Password",
            message: "Re-enter the password to confirm."
        ) else { return .cancelled }
        guard pw == confirm else {
            return .failed("Passwords did not match.")
        }
        guard !pw.isEmpty else { return .failed("Password cannot be empty.") }

        do {
            let secrets = viewModel.secrets
            let backupSecrets = secrets.map { s in
                BackupSecret(
                    key: s.key, value: s.value, comment: s.comment,
                    tags: s.tags, secretMetadata: s.secretMetadata,
                    environment: s.environment ?? config.environment,
                    projectId: config.projectId,
                    secretPath: config.secretPath
                )
            }
            let payload = BackupPayload(
                backendId: config.storeBackend,
                secrets: backupSecrets
            )
            let blob = try BackupArchive.encode(payload, password: pw)
            try blob.write(to: url, options: .atomic)
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o600], ofItemAtPath: url.path
            )
            return .success(count: backupSecrets.count, url: url)
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    static func runRestore(viewModel: AppViewModel, overwrite: Bool) async -> BackupResult {
        guard let config = AppConfiguration.load() else {
            return .failed("Configure Kubera first.")
        }

        let panel = NSOpenPanel()
        panel.title = "Open Kubera Backup"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        guard panel.runModal() == .OK, let url = panel.url else {
            return .cancelled
        }
        guard let pw = promptPassword(
            title: "Backup Password",
            message: "Enter the password used to encrypt this archive."
        ), !pw.isEmpty else { return .cancelled }

        do {
            let blob = try Data(contentsOf: url)
            let payload = try BackupArchive.decode(blob, password: pw)
            let store = SecretStoreFactory.make(for: config)

            if config.isLocalBackend, let local = store as? KeychainSecretStore {
                let count = try await local.importBackup(payload.secrets, overwrite: overwrite)
                await viewModel.loadSecrets()
                return .success(count: count, url: url)
            }

            var imported = 0
            for item in payload.secrets {
                let expiry = expiryDate(item)
                let svc = serviceURL(item)
                do {
                    if overwrite {
                        try await store.updateSecret(
                            name: item.key, value: item.value,
                            comment: item.comment ?? "", tagIds: [],
                            expiryDate: expiry, serviceURL: svc, metadataExplicit: true,
                            environment: item.environment, projectId: item.projectId,
                            secretPath: item.secretPath
                        )
                    } else {
                        try await store.createSecret(
                            name: item.key, value: item.value,
                            comment: item.comment ?? "", tagIds: [],
                            expiryDate: expiry, serviceURL: svc,
                            environment: item.environment, projectId: item.projectId,
                            secretPath: item.secretPath
                        )
                    }
                    imported += 1
                } catch {
                    // Best-effort — surface in summary.
                    continue
                }
            }
            await viewModel.loadSecrets()
            return .success(count: imported, url: url)
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    // MARK: - Password prompt

    /// Modal NSAlert with a secure text field. Returns nil if user cancels.
    private static func promptPassword(title: String, message: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        alert.accessoryView = field
        alert.addButton(withTitle: "Continue")
        alert.addButton(withTitle: "Cancel")
        // Focus the password field so the user can start typing immediately.
        DispatchQueue.main.async { alert.window.makeFirstResponder(field) }
        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return nil }
        return field.stringValue
    }

    private static func defaultBackupName() -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        return "kubera-\(f.string(from: Date())).kubera"
    }

    private static func expiryDate(_ s: BackupSecret) -> Date? {
        guard let raw = s.secretMetadata?
                .first(where: { $0.key == SecretMetadataKey.expiryDate })?.value,
              !raw.isEmpty else { return nil }
        return SecretMetadataDateFormatter.date(from: raw)
    }

    private static func serviceURL(_ s: BackupSecret) -> String? {
        s.secretMetadata?.first(where: { $0.key == SecretMetadataKey.serviceUrl })?.value
    }
}
