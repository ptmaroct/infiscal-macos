#!/bin/bash
# Creates a Kubera.app bundle from the swift build output.
# Embeds the `kubera` CLI binary at Contents/Resources/kubera so install.sh
# can symlink it into the user's $PATH.
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/.build/debug"
APP_DIR="$PROJECT_DIR/build/Kubera.app"

# Clean previous bundle
rm -rf "$APP_DIR"

# Create app bundle structure
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

# GUI binary (CFBundleExecutable=KuberaApp).
cp "$BUILD_DIR/KuberaApp" "$APP_DIR/Contents/MacOS/KuberaApp"

# CLI binary lives inside the .app so the installer can symlink to it.
if [ -f "$BUILD_DIR/kubera" ]; then
    cp "$BUILD_DIR/kubera" "$APP_DIR/Contents/Resources/kubera"
    chmod +x "$APP_DIR/Contents/Resources/kubera"
fi

# Info.plist
cp "$PROJECT_DIR/Kubera/Info.plist" "$APP_DIR/Contents/Info.plist"

# Resource bundle if present (SwiftPM generated for asset access).
if [ -d "$BUILD_DIR/Kubera_KuberaApp.bundle" ]; then
    cp -R "$BUILD_DIR/Kubera_KuberaApp.bundle" "$APP_DIR/Contents/Resources/"
fi

# App icon
if [ -f "$PROJECT_DIR/Kubera/Assets.xcassets/AppIcon.icns" ]; then
    cp "$PROJECT_DIR/Kubera/Assets.xcassets/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
fi

# Ad-hoc sign so Gatekeeper on macOS 14.4+/15 accepts the unsigned bundle
# instead of flagging it as "damaged" and offering to move it to Trash.
codesign --force --deep --sign - "$APP_DIR/Contents/Resources/kubera" 2>/dev/null || true
codesign --force --deep --sign - "$APP_DIR"

echo "App bundle created at: $APP_DIR"
echo "Run with: open $APP_DIR"
echo "CLI inside bundle:    $APP_DIR/Contents/Resources/kubera"
