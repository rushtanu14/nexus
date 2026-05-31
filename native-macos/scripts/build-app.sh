#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build/arm64-apple-macosx/debug"
APP_DIR="$ROOT_DIR/dist/Nexus.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
ICON_SOURCE="$ROOT_DIR/Sources/LocalWorkflowStudioNative/Resources/AppIcon.png"
ICONSET_DIR="$ROOT_DIR/.build/AppIcon.iconset"
ICNS_PATH="$RESOURCES_DIR/AppIcon.icns"
RESOURCE_BUNDLE="LocalWorkflowStudioNative_LocalWorkflowStudioNative.bundle"

cd "$ROOT_DIR"
swift build --product LocalWorkflowStudioNative

if [[ -d "$APP_DIR" ]]; then
  case "$APP_DIR" in
    "$ROOT_DIR"/dist/*) rm -rf "$APP_DIR" ;;
    *) echo "Refusing to remove unexpected path: $APP_DIR" >&2; exit 1 ;;
  esac
fi

mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$ICONSET_DIR"
cp "$BUILD_DIR/LocalWorkflowStudioNative" "$MACOS_DIR/LocalWorkflowStudioNative"
cp "$ROOT_DIR/AppBundle/Info.plist" "$CONTENTS_DIR/Info.plist"
cp -R "$BUILD_DIR/$RESOURCE_BUNDLE" "$CONTENTS_DIR/$RESOURCE_BUNDLE"

sips -z 16 16 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null
sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
sips -z 64 64 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null
cp "$ICON_SOURCE" "$ICONSET_DIR/icon_512x512@2x.png"
iconutil -c icns "$ICONSET_DIR" -o "$ICNS_PATH"
cp "$ICON_SOURCE" "$RESOURCES_DIR/AppIcon.png"

touch "$APP_DIR"
echo "$APP_DIR"
