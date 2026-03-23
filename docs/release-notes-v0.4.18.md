## MacLev v0.4.18

### Changes
- Fixes an idle SwiftUI and WebKit feedback loop that could keep MacLev near a full CPU core while the window was open.
- Skips no-op tab and settings writes so unchanged browser state no longer causes extra redraws or disk persistence.
- Stamps the packaged app bundle with an explicit version and build number for local and release builds.

### Install
```bash
brew tap aureuma/maclev
brew install --cask maclev
```

### Launch
```bash
open /Applications/maclev.app
```
