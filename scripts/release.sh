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
cp ".build/release/Kubera" "$APP_DIR/Contents/MacOS/Kubera"
cp "Kubera/Info.plist" "$APP_DIR/Contents/Info.plist"
if [[ -d ".build/release/Kubera_Kubera.bundle" ]]; then
  cp -R ".build/release/Kubera_Kubera.bundle" "$APP_DIR/Contents/Resources/"
fi
if [[ -f "Kubera/Assets.xcassets/AppIcon.icns" ]]; then
  cp "Kubera/Assets.xcassets/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
fi

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

cat <<EOF

==> Homebrew cask block (paste into ptmaroct/homebrew-kubera Casks/kubera.rb):

cask "kubera" do
  version "$VERSION"
  sha256 "$SHA"
  url "https://github.com/ptmaroct/infiscal-macos/releases/download/v#{version}/Kubera.dmg"
  name "Kubera"
  desc "Native macOS menubar app for Infisical secrets"
  homepage "https://github.com/ptmaroct/infiscal-macos"

  depends_on formula: "infisical"
  depends_on macos: ">= :ventura"

  app "Kubera.app"

  postflight do
    system_command "/usr/bin/xattr", args: ["-dr", "com.apple.quarantine", "#{appdir}/Kubera.app"]
  end

  zap trash: [
    "~/Library/Preferences/com.anujsharma.Kubera.plist",
    "~/Library/Application Support/Kubera",
  ]
end

EOF
