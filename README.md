# macLev

A minimal, self-contained macOS floating browser window app built with SwiftUI + WebKit.

- Keeps window above other apps when enabled (floating mode).
- Contains a simple in-app allowlist check that can block navigation to hosts not on the list.
- No external libraries.

## Versions
- Minimum target: macOS 13 (if your current environment is macOS 15, this supports the latest + two versions back).

## Build & run

From Terminal:

```bash
cd ~/Downloads/macLev
swift run
```

Or run from Xcode:

```bash
open Package.swift
```
Then choose a Mac scheme and click Run.

## Build bundled app

```bash
cd ~/Downloads/macLev
chmod +x build_app.sh
./build_app.sh
```

This creates `build/macLev.app` and launches it.

## Notes
- This app is a local, self-contained example, not an AppKit plugin loader.
- Network policy in this project blocks only browser navigation via a host allowlist; it is not a firewall.
