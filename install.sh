#!/usr/bin/env bash
# Kubera installer
# Usage: curl -fsSL https://raw.githubusercontent.com/ptmaroct/infiscal-macos/main/install.sh | bash
set -euo pipefail

REPO="ptmaroct/infiscal-macos"
DMG_URL="https://github.com/${REPO}/releases/latest/download/Kubera.dmg"
APP_NAME="Kubera.app"
INSTALL_DIR="/Applications"

bold()  { printf "\033[1m%s\033[0m\n" "$*"; }
info()  { printf "  \033[36m→\033[0m %s\n" "$*"; }
ok()    { printf "  \033[32m✓\033[0m %s\n" "$*"; }
warn()  { printf "  \033[33m!\033[0m %s\n" "$*"; }
err()   { printf "  \033[31m✗\033[0m %s\n" "$*" >&2; }

trap 'err "install failed at line $LINENO"' ERR

bold "Kubera installer"
echo

# -- Preflight --------------------------------------------------------------
if [[ "$(uname -s)" != "Darwin" ]]; then
  err "Kubera is macOS only."
  exit 1
fi

major=$(sw_vers -productVersion | cut -d. -f1)
if [[ "$major" -lt 13 ]]; then
  err "macOS 13 (Ventura) or later required. Detected $(sw_vers -productVersion)."
  exit 1
fi

arch=$(uname -m)
if [[ "$arch" != "arm64" && "$arch" != "x86_64" ]]; then
  err "Unsupported arch: $arch"
  exit 1
fi
ok "macOS $(sw_vers -productVersion) ($arch)"

# -- Infisical CLI ----------------------------------------------------------
if command -v infisical >/dev/null 2>&1; then
  ok "Infisical CLI present ($(infisical --version 2>/dev/null | head -1 || echo 'installed'))"
else
  info "Infisical CLI not found — installing"
  if ! command -v brew >/dev/null 2>&1; then
    warn "Homebrew not found. It is the easiest way to install the Infisical CLI."
    if [[ -t 0 ]]; then
      read -r -p "  Install Homebrew now? [y/N] " reply </dev/tty
    else
      reply="n"
    fi
    if [[ "${reply:-n}" =~ ^[Yy]$ ]]; then
      /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
      # add brew to PATH for this shell
      if [[ -x /opt/homebrew/bin/brew ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
      elif [[ -x /usr/local/bin/brew ]]; then
        eval "$(/usr/local/bin/brew shellenv)"
      fi
    else
      err "Cannot proceed without Homebrew. See https://infisical.com/docs/cli/overview for manual install, then re-run."
      exit 1
    fi
  fi
  brew install infisical
  ok "Infisical CLI installed"
fi

# -- Download Kubera DMG ----------------------------------------------------
tmpdir=$(mktemp -d -t kubera-install)
trap 'rm -rf "$tmpdir"' EXIT
dmg="$tmpdir/Kubera.dmg"

info "Downloading latest Kubera release"
if ! curl -fsSL --retry 3 --progress-bar "$DMG_URL" -o "$dmg"; then
  err "Failed to download Kubera.dmg from $DMG_URL"
  exit 1
fi
ok "Downloaded $(du -h "$dmg" | awk '{print $1}')"

# -- Mount & install --------------------------------------------------------
info "Mounting DMG"
mount_output=$(hdiutil attach -nobrowse -readonly "$dmg")
mount_point=$(echo "$mount_output" | tail -1 | awk '{ $1=""; $2=""; sub(/^  /, ""); print }')

cleanup_mount() {
  if [[ -n "${mount_point:-}" && -d "$mount_point" ]]; then
    hdiutil detach -quiet "$mount_point" || true
  fi
}
trap 'cleanup_mount; rm -rf "$tmpdir"' EXIT

src="$mount_point/$APP_NAME"
if [[ ! -d "$src" ]]; then
  err "Kubera.app not found inside DMG (mounted at $mount_point)"
  exit 1
fi

dest="$INSTALL_DIR/$APP_NAME"
if [[ -d "$dest" ]]; then
  warn "Existing Kubera.app found — replacing"
  rm -rf "$dest"
fi

info "Copying to $INSTALL_DIR"
cp -R "$src" "$dest"

cleanup_mount
trap 'rm -rf "$tmpdir"' EXIT

# -- Strip quarantine (unsigned app) ----------------------------------------
xattr -dr com.apple.quarantine "$dest" 2>/dev/null || true
ok "Installed Kubera.app to $INSTALL_DIR"

# -- Done -------------------------------------------------------------------
echo
bold "Done. Next steps:"
echo
if ! infisical user 2>/dev/null | grep -qi "logged in"; then
  echo "  1. Sign in to Infisical:    infisical login"
  echo "  2. Launch Kubera:           open -a Kubera"
else
  echo "  1. Launch Kubera:           open -a Kubera"
fi
echo "  3. Optional global hotkey:  System Settings → Privacy & Security → Accessibility → enable Kubera"
echo
