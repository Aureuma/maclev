## MacLev v0.4.8

### Changes
- Moves app icon files into committed `assets/` so builds use fixed icon assets instead of regenerating them.
- Removes old source-image and fallback icon generation logic from the packaging flow.
- Keeps the address bar expansion and smaller always-on-top toggle from the latest UI pass.

### Install
```bash
brew tap aureuma/maclev
brew install --cask maclev
```

### Launch
```bash
open /Applications/maclev.app
```
