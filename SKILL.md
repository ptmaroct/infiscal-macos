---
name: kubera
description: Read, write, and manage Infisical secrets through the `kubera` CLI. Use when the user mentions secrets, env vars, `.env` files, Infisical, or asks to fetch/update API keys for local dev. Wraps the `kubera` binary that Kubera.app installs onto $PATH.
version: 1.0.0
---

# Kubera CLI

Kubera is a macOS menubar app + CLI that drives [Infisical](https://infisical.com) using the user's existing `infisical` login. Both binaries share `~/.config/kubera/config.json`, so the project, environment, and "default-for-add" env are configured once in the menubar app and reused everywhere.

## Preflight

Before doing anything else, verify the CLI is reachable and the user is logged in:

```bash
kubera status
```

Possible outcomes and how to react:

- `infisical CLI: MISSING` → tell the user to `brew install infisical`. Do not try to install it yourself unless the user agrees.
- `logged in: no` → run `kubera login` (this opens a browser).
- `project: <not configured>` → run `kubera projects` to list options, then `kubera config set --project <id> --env <slug>` (or ask the user to open the macOS app and configure once).

If `environment` shows `All Environments` (`*` sentinel), every read fans out across env slugs and stamps each result with its env. Writes (`set`, `rm`) require a concrete env — pass `--env <slug>` or rely on the **Default for Add** preference saved in the GUI.

## Reading secrets

| Goal | Command |
|------|---------|
| List keys (no values) | `kubera ls` |
| List with values | `kubera ls --values` |
| Filter by tag | `kubera ls --tag <slug>` (repeat for OR) |
| Print one value | `kubera get <KEY>` |
| Copy to clipboard (pbcopy) | `kubera copy <KEY>` |
| Full metadata (version, comment, tags, expiry, service URL) | `kubera info <KEY>` |

`get`, `ls`, `info` accept `--env <slug>` to override; `info` and `ls` accept `--json` for machine-readable output.

**Safety:** never echo secret values into chat, commits, or PR descriptions. Prefer `kubera copy` or `kubera run -- <cmd>` over `kubera get` when the value would otherwise land in the conversation transcript.

## Writing secrets

| Goal | Command |
|------|---------|
| Create or update (upsert) | `kubera set <KEY> <VALUE>` |
| Read value from stdin | `echo "$VALUE" \| kubera set <KEY> -` |
| Add comment | `kubera set <KEY> <VALUE> --comment "rotated 2026-05-01"` |
| Tag the secret | `kubera set <KEY> <VALUE> --tag <id> --tag <id>` |
| Delete | `kubera rm <KEY> --force` |
| Pick env explicitly | `kubera set <KEY> <VALUE> --env prod` |

Writes require a single env. If config is in All-Environments mode, the CLI errors and asks for `--env`.

## Running with secrets injected

```bash
kubera run -- npm run dev
kubera run --env staging -- bun run start
kubera run -- printenv DATABASE_URL
```

`run` fetches secrets for the configured (or overridden) env, merges them into the child's environment on top of inherited vars, then execs the command.

## Exporting

```bash
kubera export --format dotenv > .env          # KEY=value lines
kubera export --format json                   # { KEY: value }
kubera export --format shell                  # export KEY='value'
kubera export --env prod --format dotenv > .env.prod
```

`.env` files written this way are unencrypted — make sure they're gitignored before recommending the user commit them.

## Tags and projects

```bash
kubera projects                  # list projects in the current org
kubera envs                      # envs for the configured project
kubera tags                      # list tags
kubera tags create staging-only  # create tag (single-project mode)
```

## Config

```bash
kubera config show                                    # text
kubera config show --json                             # JSON
kubera config set --project <id> --env dev --path /
kubera config set --base-url https://eu.infisical.com # self-hosted / EU
kubera config clear                                   # wipe ~/.config/kubera/config.json
```

`kubera open` launches the macOS app; `kubera open --dashboard` opens the Infisical web dashboard for the configured project.

## Common recipes

- **Bootstrap a `.env` for a new repo**:
  ```bash
  kubera export --format dotenv > .env
  echo .env >> .gitignore
  ```
- **Run dev server with prod-like creds for one command**:
  ```bash
  kubera run --env staging -- npm run dev
  ```
- **Rotate one key safely**:
  ```bash
  kubera info DB_PASSWORD              # check current version + expiry
  kubera set DB_PASSWORD <new-value>   # upsert (existing key → update)
  ```
- **Audit which secrets expire soon**:
  ```bash
  kubera ls --json | jq '.[] | select(.expiryDate)'
  ```

## What this skill is NOT for

- Don't use it to manage the `infisical` CLI itself (login flows, org switching). Defer to `infisical` directly when the question is about Infisical authentication.
- Don't use it for non-Kubera macOS app concerns (UI tweaks, menubar layout, Touch ID setup) — that's GUI territory.
