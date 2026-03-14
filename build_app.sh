#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

ICON_SOURCE="maclev-logo-square.png"
ICONSET_DIR="build/AppIcon.iconset"
ICON_FILE="build/maclev.app/Contents/Resources/AppIcon.icns"
OPEN_APP="${OPEN_APP:-1}"

if [[ ! -f "$ICON_SOURCE" ]]; then
    echo "Missing app icon source: $ICON_SOURCE" >&2
    exit 1
fi

swift build --disable-sandbox -c release
mkdir -p build/maclev.app/Contents/{MacOS,Resources}
cp .build/release/maclev build/maclev.app/Contents/MacOS/maclev

rm -rf "$ICONSET_DIR"
mkdir -p "$ICONSET_DIR"

for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$ICON_SOURCE" --out "$ICONSET_DIR/icon_${size}x${size}.png" >/dev/null
    double_size=$((size * 2))
    sips -z "$double_size" "$double_size" "$ICON_SOURCE" --out "$ICONSET_DIR/icon_${size}x${size}@2x.png" >/dev/null
done

cp "$ICON_SOURCE" "$ICONSET_DIR/icon_512x512@2x.png"
iconutil -c icns "$ICONSET_DIR" -o "$ICON_FILE"

cat > build/maclev.app/Contents/Info.plist <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>maclev</string>
    <key>CFBundleIdentifier</key>
    <string>com.aureuma.maclev</string>
    <key>CFBundleName</key>
    <string>maclev</string>
    <key>CFBundleDisplayName</key>
    <string>maclev</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
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

chmod +x build/maclev.app/Contents/MacOS/maclev

if [[ "$OPEN_APP" == "1" ]]; then
    open build/maclev.app
fi
