#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname "$0")" && pwd)"
APP_NAME="FloatingTimers"
BUILD_CONFIGURATION="release"
APP_DIR="$ROOT_DIR/dist/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
INFO_PLIST_SOURCE="$ROOT_DIR/Packaging/Info.plist"
LOCAL_HOME="$ROOT_DIR/.cache/local-home"
LOCAL_SWIFTPM_CONFIG="$LOCAL_HOME/Library/org.swift.swiftpm/configuration"
LOCAL_SWIFTPM_SECURITY="$LOCAL_HOME/Library/org.swift.swiftpm/security"
LOCAL_SWIFTPM_CACHE="$LOCAL_HOME/Library/Caches/org.swift.swiftpm"
LOCAL_CLANG_CACHE="$LOCAL_HOME/.cache/clang/ModuleCache"

cd "$ROOT_DIR"

mkdir -p "$LOCAL_SWIFTPM_CONFIG" "$LOCAL_SWIFTPM_SECURITY" "$LOCAL_SWIFTPM_CACHE" "$LOCAL_CLANG_CACHE"

export HOME="$LOCAL_HOME"
export CLANG_MODULE_CACHE_PATH="$LOCAL_CLANG_CACHE"

swift build -c "$BUILD_CONFIGURATION" --product "$APP_NAME"

BIN_PATH="$(find "$ROOT_DIR/.build" -type f -path "*/$BUILD_CONFIGURATION/$APP_NAME" | head -n 1)"

if [[ -z "${BIN_PATH:-}" ]]; then
    echo "Could not find built binary for $APP_NAME." >&2
    exit 1
fi

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$BIN_PATH" "$MACOS_DIR/$APP_NAME"
chmod +x "$MACOS_DIR/$APP_NAME"
cp "$INFO_PLIST_SOURCE" "$CONTENTS_DIR/Info.plist"

if command -v codesign >/dev/null 2>&1; then
    codesign --force --deep --sign - "$APP_DIR" >/dev/null 2>&1 || true
fi

echo "Built app bundle:"
echo "$APP_DIR"
