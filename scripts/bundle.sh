#!/bin/bash
# Creates an Kubera.app bundle from the swift build output
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

# Copy binary
cp "$BUILD_DIR/Kubera" "$APP_DIR/Contents/MacOS/Kubera"

# Copy Info.plist
cp "$PROJECT_DIR/Kubera/Info.plist" "$APP_DIR/Contents/Info.plist"

# Copy resource bundle if present
if [ -d "$BUILD_DIR/Kubera_Kubera.bundle" ]; then
    cp -R "$BUILD_DIR/Kubera_Kubera.bundle" "$APP_DIR/Contents/Resources/"
fi

# Copy app icon
if [ -f "$PROJECT_DIR/Kubera/Assets.xcassets/AppIcon.icns" ]; then
    cp "$PROJECT_DIR/Kubera/Assets.xcassets/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
fi

echo "App bundle created at: $APP_DIR"
echo "Run with: open $APP_DIR"
