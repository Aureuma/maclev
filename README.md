# MacLev

`MacLev` is a lightweight floating browser for macOS.

## What it does
- Opens web pages in a simple desktop browser window.
- Supports an always-on-top mode for the app's own window.
- Includes basic browser controls: back, forward, reload/stop, home, and direct URL entry.
- Uses SwiftUI and WebKit with no third-party dependencies.
- Supports WebKit camera and microphone permission prompts for websites.

## Notes
- `Always on top` only affects the `MacLev` window itself.
- This app does not pin or control windows from other apps.

## How to use
1. Open `MacLev`.
2. Enter a URL such as `https://www.nasa.gov`.
3. Press `Return` in the address bar to navigate.
4. Use `Always on top` if you want the browser window to float above other windows.

## Build
- `cd ~/Downloads/maclev`
- `swift build -c release`
- `swift run`

## Build app bundle
- `cd ~/Downloads/maclev`
- `./build_app.sh`

This creates a local app bundle in `build/.bundle/maclev.app` using the committed icon assets at `assets/`.

## Install with Homebrew
- `brew tap aureuma/maclev`
- `brew install --cask maclev`

Launch it with:
- `open /Applications/maclev.app`
