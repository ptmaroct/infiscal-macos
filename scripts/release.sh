#!/usr/bin/env bash
# Builds release Kubera.dmg and prints Homebrew cask metadata.
# Usage: bash scripts/release.sh v1.3.0
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: $0 vX.Y.Z" >&2
  exit 1
fi

TAG="$1"
VERSION="${TAG#v}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$SCRIPT_DIR")"
cd "$ROOT"

echo "==> Building release binary"
swift build -c release

echo "==> Bundling Kubera.app"
# Re-point bundle.sh's BUILD_DIR to release config
APP_DIR="$ROOT/build/release/Kubera.app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp ".build/release/KuberaApp" "$APP_DIR/Contents/MacOS/KuberaApp"
if [[ -f ".build/release/kubera" ]]; then
  cp ".build/release/kubera" "$APP_DIR/Contents/Resources/kubera"
  chmod +x "$APP_DIR/Contents/Resources/kubera"
fi
cp "Kubera/Info.plist" "$APP_DIR/Contents/Info.plist"
if [[ -d ".build/release/Kubera_KuberaApp.bundle" ]]; then
  cp -R ".build/release/Kubera_KuberaApp.bundle" "$APP_DIR/Contents/Resources/"
fi
if [[ -f "Kubera/Assets.xcassets/AppIcon.icns" ]]; then
  cp "Kubera/Assets.xcassets/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
fi

echo "==> Ad-hoc signing bundle"
# Required so macOS 14.4+/15 Gatekeeper does not flag the unsigned app as
# "damaged" and prompt the user to move it to Trash on first launch.
codesign --force --deep --sign - "$APP_DIR/Contents/Resources/kubera" 2>/dev/null || true
codesign --force --deep --sign - "$APP_DIR"

echo "==> Creating DMG"
DMG="$ROOT/build/Kubera.dmg"
rm -f "$DMG"
STAGE=$(mktemp -d -t kubera-dmg)
cp -R "$APP_DIR" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Kubera" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

SHA=$(shasum -a 256 "$DMG" | awk '{print $1}')
SIZE=$(du -h "$DMG" | awk '{print $1}')

echo
echo "==> Built $DMG ($SIZE)"
echo "    sha256: $SHA"
echo

if command -v gh >/dev/null 2>&1; then
  echo "==> Publishing GitHub release $TAG"
  gh release create "$TAG" "$DMG" \
    --title "$TAG" \
    --notes "Kubera $VERSION" \
    || echo "    (release may already exist; upload assets manually if needed)"
else
  echo "    gh CLI not found — upload $DMG to GitHub release $TAG manually."
fi

CASK_BODY=$(cat <<EOF
cask "kubera" do
  version "$VERSION"
  sha256 "$SHA"
  url "https://github.com/ptmaroct/kubera/releases/download/v#{version}/Kubera.dmg"
  name "Kubera"
  desc "Native macOS menubar app for Infisical secrets"
  homepage "https://github.com/ptmaroct/kubera"

  depends_on formula: "infisical"
  depends_on macos: ">= :ventura"

  app "Kubera.app"
  binary "#{appdir}/Kubera.app/Contents/Resources/kubera", target: "kubera"

  postflight do
    system_command "/usr/bin/xattr", args: ["-dr", "com.apple.quarantine", "#{appdir}/Kubera.app"]
  end

  zap trash: [
    "~/Library/Preferences/com.anujsharma.Kubera.plist",
    "~/Library/Application Support/Kubera",
  ]
end
EOF
)

TAP_REPO="${KUBERA_TAP_REPO:-ptmaroct/homebrew-kubera}"
if command -v gh >/dev/null 2>&1; then
  echo "==> Bumping Homebrew tap $TAP_REPO to $VERSION"
  TAP_DIR=$(mktemp -d -t kubera-tap)
  if gh repo clone "$TAP_REPO" "$TAP_DIR" -- --quiet; then
    mkdir -p "$TAP_DIR/Casks"
    printf '%s\n' "$CASK_BODY" > "$TAP_DIR/Casks/kubera.rb"
    if git -C "$TAP_DIR" diff --quiet -- Casks/kubera.rb; then
      echo "    cask already at $VERSION — no change"
    else
      git -C "$TAP_DIR" add Casks/kubera.rb
      git -C "$TAP_DIR" -c user.email="release-bot@kubera" -c user.name="kubera-release" \
        commit -m "kubera $VERSION" >/dev/null
      if git -C "$TAP_DIR" push --quiet; then
        echo "    pushed cask bump to $TAP_REPO"
      else
        echo "    push failed — cask block printed below for manual update" >&2
        printf '\n%s\n\n' "$CASK_BODY"
      fi
    fi
    rm -rf "$TAP_DIR"
  else
    echo "    clone failed — cask block printed below for manual update" >&2
    printf '\n%s\n\n' "$CASK_BODY"
    rm -rf "$TAP_DIR"
  fi
else
  echo "==> gh CLI not found — paste cask block into $TAP_REPO/Casks/kubera.rb:"
  printf '\n%s\n\n' "$CASK_BODY"
fi
