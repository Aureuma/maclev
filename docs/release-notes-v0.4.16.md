## MacLev v0.4.16

### Changes
- Keeps the address bar synced to the actual current page URL by observing `WKWebView.url` directly.
- Fixes sites that change routes without a full navigation callback, such as single-page apps.

### Install
```bash
brew tap aureuma/maclev
brew install --cask maclev
```

### Launch
```bash
open /Applications/maclev.app
```
