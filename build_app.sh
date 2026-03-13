#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

swift build -c release
mkdir -p build/macLev.app/Contents/{MacOS,Resources}
cp .build/release/macLev build/macLev.app/Contents/MacOS/macLev

cat > build/macLev.app/Contents/Info.plist <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>macLev</string>
    <key>CFBundleIdentifier</key>
    <string>com.example.macLev</string>
    <key>CFBundleName</key>
    <string>macLev</string>
    <key>CFBundleDisplayName</key>
    <string>macLev</string>
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

chmod +x build/macLev.app/Contents/MacOS/macLev
open build/macLev.app
