## MacLev v0.4.5

### Changes
- Implements true tabbed browsing in-browser with per-tab state isolation (address, back/forward, loading state, navigation title).
- Adds common browser keyboard shortcuts (new tab, close tab, tab switching) without adding extra UI overhead.
- Adds a compact horizontal tab strip where each tab card is fully clickable, including close affordances.
- Enables page title updates from `WKWebView` so tab titles reflect loaded page titles.
- Adds basic tab navigation keyboard shortcuts and keeps browser controls grouped in a compact top bar.

### Known behavior
- Tab switching keeps each tab's navigation stack isolated in its own `WKWebView` lifecycle while visible.
- The floating window toggle remains available in top controls.
- Back/forward are command key shortcuts and the reload/stop toggle remains in the address bar.

### Install
```bash
brew tap aureuma/maclev
brew install --cask maclev
```

### Launch
```bash
open /Applications/maclev.app
```
