# Mini

A small, quiet macOS browser for one person. Chromium renders the pages; everything you touch is native: an AppKit window, a SwiftUI sidebar, Liquid Glass materials, and keyboard focus that behaves like a Mac app.

Mini is an open source exploration project: a personal, minimal browser built to explore a native Swift shell over Chromium (CEF).

- Vertical sidebar with nested tabs (a tree), pinned tabs as favicon tiles
- Command bar for URLs, search (with Google suggestions) and switching tabs
- Built-in ad and tracker blocking (uBlock Origin, EasyList and EasyPrivacy lists)
- Fill logins from Apple Passwords through a native card with Touch ID
- Native permission prompts for camera, microphone, location and the rest
- Session restore with lazy tabs, so launch stays fast
- Tabs left unselected for 12 hours archive themselves; find them again in the command bar
- Downloads progress in the sidebar; click to cancel, or to show the file in Finder
- A crashed page shows a Reload button instead of a blank tab
- Web notifications appear as macOS notifications after you allow them for a site (View > Allow Notifications from This Site turns them on or off); clicking one returns you to its tab
- A one-line weather row at the bottom of the sidebar (Open-Meteo, city-level location; click to search the weather)
- No extensions, sync, accounts or settings window

## Download

Signed and notarized builds for Apple Silicon (macOS 26 or later) are on the [Releases](https://github.com/Isaac-Harper/mini/releases) page. Unzip, move Mini to Applications and open it. There is no auto-update.

## Requirements

- macOS 26 or later on Apple Silicon
- Xcode 27 (Swift 6.4)
- Rust (stable) via rustup or Homebrew
- `cmake` and `ninja`: `brew install cmake ninja`

## Build and run

```sh
make run
```

The first build downloads the Chromium Embedded Framework (about 300 MB) into `~/.local/share/cef` and compiles its C++ wrapper, so it takes a few minutes. Later builds are incremental.

| Command | What it does |
| --- | --- |
| `make` | Builds the Rust core, the Swift shell, and assembles `build/Mini.app` |
| `make run` | Builds, then opens the app |
| `make release VERSION=X.Y.Z` | Builds with a secure timestamp, notarizes and staples the app, and publishes `Mini-X.Y.Z-arm64.zip` as a GitHub release (needs a clean, pushed tree and the `lowlight-notary` profile) |
| `make install` | Builds, quits a running Mini, copies it to `/Applications`, registers it with Launch Services and relaunches it |
| `make CONFIG=debug run` | Debug build |
| `make clean` | Removes all build output |

The build signs with the first Developer ID Application or Apple Development identity in your keychain, so the Keychain grant for Mini's cookie key survives rebuilds. Set `MINI_SIGN_IDENTITY` to pick another identity. Without one it signs ad hoc, and every rebuild asks for Keychain access again; until that prompt is answered, pages never load.

To use Mini as your default browser, run `make install` and choose Mini > Set as Default Browser.

## Keyboard

| Shortcut | Action |
| --- | --- |
| ⌘T | New tab (command bar) |
| ⌥⌘T | New child tab |
| ⌘L | Edit the current address |
| ⌘W | Close tab (pinned tabs reset instead) |
| ⇧⌘T | Reopen closed tab |
| ⌃Tab, ⌃⇧Tab, ⌥⌘↓, ⌥⌘↑ | Next and previous tab |
| ⌘1 to ⌘9 | Select tab (pinned first; ⌘9 is the last) |
| ⌥⌘→, ⌥⌘← | Indent and outdent |
| ⌥⌘\ | Collapse or expand a group |
| ⌃⌘P | Pin or unpin tab |
| ⌃⌘S | Show or hide the sidebar |
| ⌘\ | Fill password |
| ⇧⌘C | Copy the page address |
| ⌘[, ⌘] | Back and forward |
| ⌘R, ⌘. | Reload and stop |
| ⌘F, ⌘G, ⇧⌘G | Find, next, previous |
| ⌘=, ⌘-, ⌘0 | Zoom in, out, actual size (remembered per site) |
| ⌥⌘I | Developer tools |

Browser shortcuts take priority over the page, so ⌘T or ⌘W work even when a site tries to capture them. Copy, paste, undo and select all always go to the page.

## Passwords

When a page has a login form, a key button appears in the address pill. Click it or press ⌘\ and Mini shows a small card with the site's address and two native fields. Click the key icon in the password field, pick a login from Apple Passwords, confirm with Touch ID, and press Return to fill the page. Mini never shows the card on its own and never stores or logs the values.

macOS does not know which website Mini is showing, so it lists all your logins instead of suggesting the matching one. Site-matched suggestions and passkeys need Apple's macOS Web Browser Public Key Credential entitlement, which has to be requested from Apple.

Passkeys are not supported until that entitlement is granted. Mini turns off WebAuthn in pages (passkey requests fail as "not allowed" and platform authenticators report unavailable), so sites fall back to passwords and Chromium never shows its QR code or "use your phone" dialog.

## Where things live

- `~/Library/Application Support/Mini/Profile`: cookies, cache and site data
- `~/Library/Application Support/Mini/session.json`: open tabs
- `~/Library/Application Support/Mini/archive.json`: archived tabs (newest 200)
- Weather: the last reading is cached in Mini's user defaults (`WeatherReading`); coordinates are rounded to two decimals before they are sent to Open-Meteo and are never stored or logged
- `~/Library/Application Support/Mini/zoom-levels.json`: per-site zoom levels
- `~/Library/Application Support/Mini/Favicons`: cached site icons, so restored tabs show their icon before they load
- `~/Library/Application Support/Mini/permissions.json`: per-site permission decisions
- `~/Library/Application Support/Mini/Filters`: ad block lists, refreshed weekly
- `~/Downloads`: downloads, saved without asking

## Project layout

```
core/          Rust: CEF embedding, handlers, ad blocking (cargo workspace)
  include/     mini_core.h, the C interface between Rust and Swift
shell/         Swift: window, sidebar, tabs, prompts, menus (SwiftPM package)
bundle/        Info.plist for the app
scripts/       bundle.sh assembles and signs Mini.app
```

Swift owns everything you see and every focus decision. Rust owns Chromium. They talk only through `core/include/mini_core.h`. `AGENTS.md` has the architecture notes and invariants.

## Known limits

- One window and one profile.
- Web notifications only work while the page is open: Mini replaces the page's `Notification` API and `showNotification` with native macOS notifications, but a service worker cannot show notifications on its own, so push notifications for closed tabs never arrive.
- Google sometimes refuses sign-in from embedded Chromium with "This browser or app may not be secure".

## License

MIT
