# Kubera

> *Keeper of secrets — named for the Vedic god of wealth.*

A native macOS menubar app for quickly searching and managing secrets via the [Infisical](https://infisical.com) CLI.

![macOS](https://img.shields.io/badge/macOS-13%2B-black?logo=apple)
![Swift](https://img.shields.io/badge/Swift-5.9-orange?logo=swift)
![License](https://img.shields.io/badge/License-MIT-blue)

## Screenshots

<p align="center">
  <img src="assets/menubar.png" width="280" alt="Menubar dropdown" />
  &nbsp;&nbsp;
  <img src="assets/add-secret.png" width="280" alt="Add secret" />
  &nbsp;&nbsp;
  <img src="assets/settings.png" width="280" alt="Settings" />
</p>

## Features

- **Menubar native** — lives in your system menubar as an NSMenu dropdown, no dock icon
- **Instant search** — filter secrets by name as you type (local, zero-latency)
- **One-click copy** — click any secret to copy its value, auto-clears clipboard after 30s
- **View All Secrets** — full window with search, edit, delete, version numbers, and tags
- **Add secrets** — create new secrets with tags and comments without leaving your menubar
- **Edit & delete** — update secret values/comments or delete secrets from the View All window
- **Version tracking** — see the current version number for each secret
- **Tags display** — view tags on each secret
- **Global shortcut** — `Cmd + Shift + K` toggles the menu from anywhere
- **Direct dashboard link** — opens your project directly in the Infisical web dashboard
- **CLI-powered** — uses your existing `infisical` CLI session, zero credential management
- **Dark vault UI** — custom dark theme with amber accents and smooth animations

## Install

### One-liner (recommended)

```bash
curl -fsSL https://raw.githubusercontent.com/ptmaroct/kubera/main/install.sh | bash
```

Installs the Infisical CLI (via Homebrew) if missing, downloads the latest Kubera DMG, drops it into `/Applications`, and strips the macOS quarantine flag so the unsigned app launches cleanly.

### Homebrew

```bash
brew tap ptmaroct/kubera
brew install --cask kubera
```

The cask declares `infisical` as a dependency, so the CLI is pulled in automatically.

### Manual download

1. Grab the latest `Kubera.dmg` from [Releases](https://github.com/ptmaroct/kubera/releases).
2. Mount it and drag `Kubera.app` to `/Applications`.
3. Because the build is currently unsigned, run this once to clear Gatekeeper's "App is damaged" warning:

   ```bash
   xattr -dr com.apple.quarantine /Applications/Kubera.app
   ```

4. Install the Infisical CLI separately: `brew install infisical`.

### After install

```bash
infisical login   # one-time auth
open -a Kubera    # or launch from Spotlight
```

If you want the global `Cmd + Shift + K` hotkey: **System Settings → Privacy & Security → Accessibility → enable Kubera**.

### Requirements

- macOS 13 (Ventura) or later
- [Infisical CLI](https://infisical.com/docs/cli/overview) (installed automatically by both quick-install paths)

### Build from source

```bash
swift build
bash scripts/bundle.sh
open build/Kubera.app
```

## First Launch

1. App detects your Infisical CLI session automatically
2. Select your project and environment from dropdowns
3. Click **Connect** — secrets appear in the menubar menu

## Usage

| Action | How |
|--------|-----|
| Open menu | Click the key icon in menubar, or `Cmd + Shift + K` |
| Search | Type in the search field at the top of the menu |
| Copy secret | Click any secret name — value is copied to clipboard |
| View all secrets | Menu → View All Secrets (`Cmd + L`) |
| Edit/delete secret | Open View All, use the pencil or trash icons per row |
| Add secret | Menu → Add New Secret (`Cmd + N`) |
| Open dashboard | Menu → Open Infisical Dashboard (`Cmd + D`) |
| Settings | Menu → Settings (`Cmd + ,`) |

Clipboard auto-clears after 30 seconds for security.

## CLI

Kubera also ships a `kubera` command-line tool that reads the same project/env config you set in the menubar app (`~/.config/kubera/config.json`). Both `install.sh` and the Homebrew cask drop a symlink onto your `$PATH`, so after install:

| Command | Action |
|---------|--------|
| `kubera status` | Login state + configured project/env/base URL |
| `kubera login` / `kubera logout` | Sign in / out via the bundled `infisical` flow |
| `kubera config show` | Print resolved config (`--json` for machine-readable) |
| `kubera config set --project <id> --env dev --path / --base-url <url>` | Update fields (also writable from the GUI) |
| `kubera config clear` | Wipe `~/.config/kubera/config.json` |
| `kubera projects` | List projects you can access (`--json`) |
| `kubera envs` | Envs in the configured project |
| `kubera ls` | List secret keys (no values by default; `--values`, `--json`, `--tag <slug>`) |
| `kubera get <KEY>` | Print one value to stdout |
| `kubera copy <KEY>` | Copy to clipboard via `pbcopy` |
| `kubera info <KEY>` | Full metadata: version, comment, tags, expiry, service URL |
| `kubera set <KEY> <VALUE>` | Upsert (create or update). `<VALUE>` of `-` reads from stdin. `--comment`, `--tag <id>` |
| `kubera rm <KEY> [--force]` | Delete, with confirm prompt unless forced |
| `kubera export --format dotenv\|json\|shell` | Dump every secret in the chosen format |
| `kubera run -- <cmd> [args…]` | Inject secrets as env vars and exec the subcommand (`kubera run -- npm run dev`) |
| `kubera tags` / `kubera tags create <name>` | List or create tags |
| `kubera open` / `kubera open --dashboard` | Launch the macOS app or the Infisical web dashboard |

`kubera --help` covers the full surface. Most read commands accept `--json` for piping into `jq`. When the menu is in **All Environments** mode, set a default env in **Settings → Default for Add** so writes (`set`, `rm`) and the Add Secret form know which env to target — the CLI honors this fallback automatically.

## Claude Code skill

A [`SKILL.md`](./SKILL.md) at the repo root teaches Claude Code (and other agents that use the [vercel-labs/skills](https://github.com/vercel-labs/skills) loader) how to drive the `kubera` CLI safely — preflight checks, when to use `copy`/`run` vs `get`, recipes for `.env` bootstrap and key rotation.

Install it into your project (or globally) with the `skills` npm package:

```bash
# project-scoped — commits .claude/skills/kubera/ into the repo
npx skills add ptmaroct/kubera --agent claude-code

# global, for all projects on this machine
npx skills add ptmaroct/kubera --agent claude-code --scope user
```

The skill assumes the `kubera` binary is on `$PATH`. If it isn't yet, run the curl installer or `brew install --cask kubera` first.

## Project Structure

Three SwiftPM targets share a single core library:

```
KuberaCore/                   # Library: shared types + Infisical service
├── Models/
│   ├── Secret.swift              # SecretItem, SecretTag, SecretMetadata*
│   ├── AppConfiguration.swift    # File-backed config (~/.config/kubera/config.json)
│   └── APIModels.swift
└── Services/
    └── InfisicalCLIService.swift # REST API + CLI session helpers

Kubera/                       # GUI executable (KuberaApp target)
├── KuberaApp.swift, AppDelegate.swift
├── Models/{AppConfiguration+Shortcut, DockVisibilityPreference, ExpiryNotificationSettings}
├── Services/{TouchIDService, ClipboardService, ProjectCache, ExpiryNotificationScheduler}
├── ViewModels/, Views/, Utilities/

KuberaCLI/                    # CLI executable (kubera binary)
├── KuberaCLI.swift, Helpers.swift
└── Commands/{Status, Login, Config, Projects, Secrets}.swift
```

## Troubleshooting

**"Kubera is damaged and can't be opened"** — the build is unsigned. Run:

```bash
xattr -dr com.apple.quarantine /Applications/Kubera.app
```

The curl and Homebrew installers do this automatically; you only need it for manual DMG installs.

**Settings stuck on "Loading…"** — your Infisical CLI session is missing or expired. Run `infisical login` and reopen Settings.

**Global hotkey (`Cmd + Shift + K`) does nothing** — grant Accessibility access in **System Settings → Privacy & Security → Accessibility**.

**Custom Infisical instance (EU / self-hosted)** — set the CLI domain first:

```bash
infisical login --domain https://eu.infisical.com   # or your self-hosted URL
```

## Why is the macOS sandbox disabled?

Kubera spawns the local `infisical` binary as a subprocess to talk to your account. The macOS app sandbox blocks arbitrary subprocess execution, so it's explicitly disabled in `Kubera.entitlements`. Nothing leaves your machine — Kubera only talks to Infisical through your already-authenticated CLI session.

## License

MIT
