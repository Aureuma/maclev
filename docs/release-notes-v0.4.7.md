## MacLev v0.4.7

### Changes
- Make app icon packaging resilient when the source icon file is moved or unavailable by allowing `ICON_SOURCE` overrides and non-fatal fallback.
- Rename user-facing app name to `MacLev` across docs and app metadata.
- Keep all brew/tooling identifiers stable while improving public-facing branding.

### Install
```bash
brew tap aureuma/maclev
brew install --cask maclev
```

### Launch
```bash
open /Applications/maclev.app
```
