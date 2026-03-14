#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

APP_ICON_PATH="${APP_ICON_PATH:-assets/AppIcon.icns}"
APP_STAGING_DIR="build/.bundle"
APP_BUNDLE_PATH="$APP_STAGING_DIR/maclev.app"
ICON_FILE="$APP_BUNDLE_PATH/Contents/Resources/AppIcon.icns"
OPEN_APP="${OPEN_APP:-0}"

if [[ ! -f "$APP_ICON_PATH" ]]; then
    echo "Missing app icon asset: $APP_ICON_PATH" >&2
    echo "Keep the committed icon asset updated in assets/AppIcon.icns." >&2
    echo "If you want to override locally, set APP_ICON_PATH to another .icns file." >&2
    exit 1
fi

swift build --disable-sandbox -c release
rm -rf "$APP_STAGING_DIR"
mkdir -p "$APP_BUNDLE_PATH/Contents/"{MacOS,Resources}
cp .build/release/maclev "$APP_BUNDLE_PATH/Contents/MacOS/maclev"
cp "$APP_ICON_PATH" "$ICON_FILE"

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
