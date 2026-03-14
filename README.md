# maclev

`maclev` is a lightweight floating browser for macOS.

## What it does
- Opens web pages in a simple desktop browser window.
- Supports an always-on-top mode for the app's own window.
- Includes basic browser controls: back, forward, reload/stop, home, and direct URL entry.
- Uses SwiftUI and WebKit with no third-party dependencies.

## Notes
- `Always on top` only affects the `maclev` window itself.
- This app does not pin or control windows from other apps.

## How to use
1. Open `maclev`.
2. Enter a URL such as `https://example.com`.
3. Press `Return` or click `Go`.
4. Use `Always on top` if you want the browser window to float above other windows.

## Build
- `cd ~/Downloads/maclev`
- `swift build -c release`
- `swift run`

## Build app bundle
- `cd ~/Downloads/maclev`
- `./build_app.sh`

This creates `build/maclev.app` with the bundled app icon from `maclev-logo-square.png`.

## Install with Homebrew
- `brew tap aureuma/maclev`
- `brew install --cask maclev`

Launch it with:
- `open /Applications/maclev.app`
