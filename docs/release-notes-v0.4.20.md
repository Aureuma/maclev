## MacLev v0.4.20

### Changes
- Fixes browser window creation so each new window owns its own tabs, selection, and navigation state instead of mirroring an existing window.
- Routes popup-style `window.open()` and target-blank navigations into new browser tabs.
- Stops normal browsing from overwriting the saved startup page preference.
- Validates and normalizes the configured startup page before it is saved.
- Prevents the active page from reloading just because the SwiftUI browser view appears again.
- Separates the current window's floating state from the default floating preference used for future windows.
- Bumps the packaged app version metadata to `0.4.20`.

### Install
```bash
brew tap aureuma/maclev
brew install --cask maclev
```

### Launch
```bash
open /Applications/maclev.app
```
