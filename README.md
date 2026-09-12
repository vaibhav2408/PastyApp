# Clip20

A native macOS menu bar app that keeps your last 20 text and image copies in memory.

## Download

[Download Clip20 for Apple silicon Macs](https://github.com/vaibhav2408/PastyApp/releases/latest/download/Clip20-macOS-arm64.zip) · macOS 13 or later

Unzip the download, move `Clip20.app` to Applications, and open it. The app appears in the menu bar. Downloads from this private repository require repository access.

This build is locally signed and is not notarized by Apple. If macOS blocks it on first launch, see [Apple's instructions for opening an app from an unidentified developer](https://support.apple.com/en-gb/102445). Updates and version details are on the [Releases page](https://github.com/vaibhav2408/PastyApp/releases).

## Use

Open `dist/Clip20.app`, then copy some text or an image. Click the **C** with a small **H** in the menu bar or press **Control–Option–V** to open history. Click an item or select it with **↑ / ↓** and press **Return**. Focus returns to your previous app; press **⌘V** to paste.

- Search text by typing in the panel. Search `image` to show image entries.
- The compact panel shows up to 10 rows before scrolling and shrinks for shorter histories or search results. Hover over a text row for a longer preview.
- Delete an entry with its × button, its context menu, or **⌘Delete**.
- Right-click (or Control-click) the menu bar icon for Pause/Resume, Clear history, Open history, and Quit. The **⋯** menu has the same actions. Left-click opens the history panel.
- Copies made while paused are skipped. You can still reuse existing history.
- Every launch starts empty. Quitting removes the app's history; it leaves the current system clipboard alone.
- The app stays in the menu bar with no Dock icon. Launch at login is not enabled automatically.

## Build

Requires macOS 13 or later and Apple Command Line Tools with Swift 5.9 or later. No third-party dependencies or downloads are needed.

```sh
bash scripts/build.sh
open dist/Clip20.app
```

The build script produces an app for the current Mac and signs it locally with an ad-hoc signature. You can move it to Applications if desired. It is not notarized or company-approved by being locally built.

If your installed Swift compiler and default SDK are from different releases, select a matching SDK with `SDKROOT` when building or testing.

```sh
bash scripts/test.sh
```

Build and test scripts invoke the compiler directly, so they also work when Swift Package Manager is unavailable. The included `Package.swift` can be opened in Xcode, or used with `swift build` and `swift run Clip20Checks` on a working SwiftPM installation.

## Behavior and limits

- Captures plain text, URLs as text, code, image pixels, and local image files copied in Finder. Rich text is restored as plain text. Other file types are outside scope.
- Finder image copies retain both an in-memory image snapshot and the original file URL. Selecting one lets you paste the file into a Finder folder while the original remains available locally and unchanged. A copy containing several image files records the first image. Remote or undownloaded images must be available locally first.
- Preserves the original image bytes and resolution. Thumbnails use a small separate preview. When restoring non-PNG images, it also supplies a PNG representation for compatibility with apps that accept pasted images. If the source file is moved, deleted, or edited, the saved pixels still paste into image-compatible apps, but Finder file paste is unavailable. Images copied as pixels without a source file also paste only into image-compatible apps. Clip20 does not create temporary image files.
- Identical text and byte-identical images of the same format move to the top instead of occupying another slot.
- Stores up to 20 entries, with a 32 MB per-item limit and a 256 MB history payload limit to bound memory use. Old entries are evicted sooner if the memory limit is reached. Oversized items are skipped with a message.
- Checks clipboard changes every 350 ms. Extremely rapid clipboard changes between checks can be missed.
- Skips clipboard content marked confidential, transient, or automatically generated using [NSPasteboard conventions](https://nspasteboard.org/). This is marker-based, not password detection: unmarked passwords or secrets can still be captured. Pause capture when needed.
- No history files, database, preferences, network code, analytics, sync, or external dependencies. History is held in process memory, which macOS manages, including system-level swap.
- Uses a registered shortcut and copies back to the clipboard. It does not simulate keystrokes or request Accessibility or Screen Recording access.

## Source

`Sources/ClipboardCore` contains capture, history, and clipboard restoration. `Sources/Clip20` contains the native menu bar app and SwiftUI panel. Tests use isolated named pasteboards and synthetic content; they never read or overwrite the user's general clipboard.

Harvey styling uses the warm neutral palette from `frontend/packages/design-system/src/tokens/css/tokens.reskin.*.css`. Clip20's own logo is a large C with a smaller H at its bottom right; that secondary H uses the geometry from `frontend/packages/design-system/src/icons/harvey-logo.tsx`. Diatype and Harvey Serif are bundled from `frontend/public/fonts/harvey`, converted from WOFF2 to native TrueType with fontTools. Fonts are registered only for the app process; no fonts are installed system-wide or downloaded at runtime. The native macOS options menus retain platform behavior.

`bash scripts/preview.sh` renders light, dark, empty, search, and full-history previews using synthetic content. It also checks that both bundled fonts load. It does not capture the screen or read the general clipboard.

Built on Apple's [NSPasteboard](https://developer.apple.com/documentation/appkit/nspasteboard) and [NSStatusItem](https://developer.apple.com/documentation/appkit/nsstatusitem) APIs.
