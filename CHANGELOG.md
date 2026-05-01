# Changelog

## v1.6.0 — Local backend + Infisical optional

Kubera now runs end-to-end against either backend. Infisical is no longer required to use the app.

### Added
- **Local encrypted backend** (`KeychainSecretStore`). AES-256-GCM at `~/Library/Application Support/Kubera/local-store.kbra`; master key in macOS Keychain (`com.kubera.local`). Tags, comments, expiry, service URL all supported.
- **Onboarding backend picker** — pick "On this Mac" or "Connect to Infisical" on first launch.
- **Encrypted backup / restore** (`.kubera` archive). AES-256-GCM + PBKDF2-SHA256 (524,288 rounds). CLI: `kubera export --format=kubera --output <file>` and `kubera import <file> [--overwrite] [--dry-run]`. GUI: Settings → Storage → Backup… / Restore….
- **Local create-project / create-environment** from Settings dropdowns (`+ New Project…`, `+ New Environment…`). Works for the local backend; Infisical create-environment also wired through `POST /api/v1/workspace/{id}/environments`.
- **Switch backend** from Settings → Storage → "Connect to Infisical…" / "Switch to Local Mode".
- **Env badges in menubar** — every secret renders its env after the key.
- **Row click = edit** in All Secrets. Cleaner edit icon (`square.and.pencil`).
- **Auto-sizing windows** — Settings and New Secret resize to fit content; no extra blank space.

### Changed
- Default local environments renamed from `dev/stg/prod` to `dev/staging/prod` with display names `Development / Staging / Production`.
- "Open Infisical Dashboard" menu item is hidden when running on the local backend.
- Settings footer reads version from the bundle instead of being hardcoded.

### Internal
- New `SecretStore` protocol; both `InfisicalSecretStore` and `KeychainSecretStore` conform. All call sites (`AppViewModel`, `AddSecretViewModel`, `SecretListViewModel`, `ProjectCache`, CLI Helpers / Status / Projects / Secrets / Import) route through `SecretStoreFactory.make(for:)`.
- `tagsExplicit` flag threaded through `SecretStore.updateSecret` so callers can clear all tags.
- `AppConfiguration.storeBackend` + `iCloudSyncEnabled` fields with backwards-compatible decoder (legacy configs auto-migrate to `infisical`).

## v1.5.2

- Match Edit Secret sheet with Add Secret flow (tags, expiry, service URL).
- Pad eye-toggle inside secret value field.
- Various design + spacing fixes.
