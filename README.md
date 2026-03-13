# macLev

`macLev` is now an any-window floating utility instead of a browser.

## What it does
- Lists visible windows from running apps.
- Lets you pin/unpin a selected window above other windows.
- Supports pinning all visible windows and unpinning all at once.

## Important
- It uses private CoreGraphics APIs (`CGSSetWindowLevel`) to control other app windows.
- This is unstable across macOS releases and is not App Store safe.

## How to use
1. Open `macLev`.
2. Click `Refresh windows`.
3. Select a window from the list.
4. Click `Pin` to float it, `Unpin` to return it to normal level.
5. Optional: `Pin all visible` / `Unpin all`.

## Build
- `cd ~/Downloads/macLev`
- `swift build -c release`
- `swift run`
