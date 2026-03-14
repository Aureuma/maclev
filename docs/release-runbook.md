# MacLev Release Runbook

## Purpose

Release `MacLev` as:

- a tagged source release in `Aureuma/maclev`
- a packaged macOS app zip stored in `Aureuma/homebrew-maclev`
- a Homebrew cask update in `Aureuma/homebrew-maclev`
- a GitHub Release in `Aureuma/maclev` when GitHub API authentication is available

## Release Checklist

1. Ensure `maclev` working tree is clean.
2. Ensure `homebrew-maclev` working tree is clean.
3. Pick the next version tag, for example `v0.4.1`.
4. Build the app bundle:
   - `cd ~/Downloads/maclev`
   - `env OPEN_APP=0 ./build_app.sh`
5. Package the app bundle:
   - `ditto -c -k --sequesterRsrc --keepParent build/.bundle/maclev.app ~/Downloads/homebrew-maclev/artifacts/maclev-0.4.4.zip`
6. Compute the checksum:
   - `shasum -a 256 ~/Downloads/homebrew-maclev/artifacts/maclev-0.4.4.zip`
7. Update the cask version and checksum in `homebrew-maclev/Casks/maclev.rb`.
8. Update release notes if needed.
9. Commit and push `maclev`.
10. Tag and push the new version in `maclev`.
11. Commit and push `homebrew-maclev`.
12. Reinstall locally:
   - `brew reinstall --cask aureuma/maclev/maclev`
13. Verify installed app path:
   - `/Applications/maclev.app`
14. Create the GitHub Release in `Aureuma/maclev` if authenticated.

## Permission UX checklist

- `Ask` in permissions now follows macOS system camera/microphone permission state and does not show a custom in-app permission modal.
- For a site-specific default of `ask`, MacLev will still defer to current system permission, and the system dialog appears only when needed.
- If system permission is denied, the decision stays denied until changed in macOS System Settings.

## Release Notes Template

Use this structure for the GitHub Release body:

```md
## MacLev vX.Y.Z

### Changes
- item
- item

### Install
```bash
brew tap aureuma/maclev
brew install --cask maclev
```

### Launch
```bash
open /Applications/maclev.app
```
```

## GitHub Release Commands

If `gh` is installed and authenticated:

```bash
gh release create vX.Y.Z \
  --repo Aureuma/maclev \
  --title "MacLev vX.Y.Z" \
  --notes-file docs/release-notes-vX.Y.Z.md
```

If `gh` is not installed but a GitHub API token is available:

```bash
curl -X POST https://api.github.com/repos/Aureuma/maclev/releases \
  -H "Accept: application/vnd.github+json" \
  -H "Authorization: Bearer $GITHUB_TOKEN" \
  -d @release.json
```

## Current Packaging Model

- Source repo: `Aureuma/maclev`
- Cask repo: `Aureuma/homebrew-maclev`
- Installed app path: `/Applications/maclev.app`
- Homebrew install command:
  - `brew tap aureuma/maclev`
  - `brew install --cask maclev`
