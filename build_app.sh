#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

swift build -c release
mkdir -p build/maclev.app/Contents/{MacOS,Resources}
cp .build/release/maclev build/maclev.app/Contents/MacOS/maclev

cat > build/maclev.app/Contents/Info.plist <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>maclev</string>
    <key>CFBundleIdentifier</key>
    <string>com.example.maclev</string>
    <key>CFBundleName</key>
    <string>maclev</string>
    <key>CFBundleDisplayName</key>
    <string>maclev</string>
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
open build/maclev.app
