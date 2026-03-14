#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

ICON_SOURCE="${ICON_SOURCE:-maclev-logo-square.png}"
GENERATED_ICON="${GENERATED_ICON:-maclev-generated.icns}"
APP_STAGING_DIR="build/.bundle"
APP_BUNDLE_PATH="$APP_STAGING_DIR/maclev.app"
ICONSET_DIR="$APP_STAGING_DIR/AppIcon.iconset"
ICON_FILE="$APP_BUNDLE_PATH/Contents/Resources/AppIcon.icns"
OPEN_APP="${OPEN_APP:-0}"
HAS_ICON_SOURCE=false
HAS_GENERATED_ICON=false

if [[ -f "$ICON_SOURCE" ]]; then
    HAS_ICON_SOURCE=true
elif [[ -f "$GENERATED_ICON" ]]; then
    HAS_GENERATED_ICON=true
else
    echo "Missing app icon source: $ICON_SOURCE" >&2
    echo "Set ICON_SOURCE, provide maclev-logo-square.png, or keep a generated icon at $GENERATED_ICON." >&2
    exit 1
fi

swift build --disable-sandbox -c release
rm -rf "$APP_STAGING_DIR"
mkdir -p "$APP_BUNDLE_PATH/Contents/"{MacOS,Resources}
cp .build/release/maclev "$APP_BUNDLE_PATH/Contents/MacOS/maclev"

if [[ "$HAS_ICON_SOURCE" == "true" ]]; then
    rm -rf "$ICONSET_DIR"
    mkdir -p "$ICONSET_DIR"

    for size in 16 32 128 256 512; do
        sips -z "$size" "$size" "$ICON_SOURCE" --out "$ICONSET_DIR/icon_${size}x${size}.png" >/dev/null
        double_size=$((size * 2))
        sips -z "$double_size" "$double_size" "$ICON_SOURCE" --out "$ICONSET_DIR/icon_${size}x${size}@2x.png" >/dev/null
    done

    cp "$ICON_SOURCE" "$ICONSET_DIR/icon_512x512@2x.png"
    iconutil -c icns "$ICONSET_DIR" -o "$ICON_FILE"
elif [[ "$HAS_GENERATED_ICON" == "true" ]]; then
    cp "$GENERATED_ICON" "$ICON_FILE"
fi

cat > "$APP_BUNDLE_PATH/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>maclev</string>
    <key>CFBundleIdentifier</key>
    <string>ai.aureuma.maclev</string>
    <key>CFBundleName</key>
    <string>MacLev</string>
    <key>CFBundleDisplayName</key>
    <string>MacLev</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright 2026 Aureuma</string>
    <key>NSCameraUsageDescription</key>
    <string>MacLev uses the camera when a website asks for camera access.</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>MacLev uses the microphone when a website asks for microphone access.</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <false/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSMainNibFile</key>
    <string></string>
</dict>
</plist>
PLIST

chmod +x "$APP_BUNDLE_PATH/Contents/MacOS/maclev"

if [[ "$OPEN_APP" == "1" ]]; then
    open "$APP_BUNDLE_PATH"
fi
