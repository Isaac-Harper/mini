# Mini

A small, quiet macOS browser for one person. Chromium renders the pages; everything you touch is native: an AppKit window, a SwiftUI sidebar, Liquid Glass materials, and keyboard focus that behaves like a Mac app.

Mini is an open source exploration project: a personal, minimal browser built to explore a native Swift shell over Chromium (CEF).

- No toolbar strip: the traffic lights, sidebar toggle and back/forward sit in the sidebar's top row, and the page is a rounded card that runs to the top of the window. With the sidebar hidden, point at the top-left corner to bring the controls back, or at the left edge to slide the sidebar out over the page (click the sidebar button to keep it open)
- The sidebar takes on a light tint of the page's theme color (`<meta name="theme-color">`), off with Reduce Transparency or Increase Contrast
- Two-finger swipe left or right on the trackpad goes back or forward (when "Swipe between pages" is on in Trackpad settings and the page has nothing left to scroll that way)
- The address pill shows the site's host; hover it for the full address. Plain http pages (other than localhost) get a small Not Secure mark
- While a page loads its tab shows a spinner and a thin accent line runs along the top of the page
- Vertical sidebar with nested tabs (a tree), pinned tabs as favicon tiles; drag rows to reorder, onto a row to nest, or onto the pinned area to pin
- Three kinds of tabs: pinned tiles, saved tabs and regular tabs. Saved tabs sit in their own "Saved" section under the pins, can nest, are never auto-archived, and ⌘W only unloads one back to its saved page (the dimmed row stays; a small arrow on the row goes back to the saved page after you navigate away). "Remove from Saved" or "Delete" in the row's menu let go of one for real. Drag between sections to change a tab's kind; regular tabs idle for 12 hours are archived
- Links opened from other apps open in a little floating window with back, forward and an Open in Mini button (⌘O) that moves the live page into a tab
- Spaces (Personal and Work to start), each with its own tabs, pins and its own cookies and logins; switch with the buttons at the bottom of the sidebar or ⌃1 to ⌃9
- Swipe two fingers left or right on the sidebar to move to the next or previous space
- Drag a tab out of the sidebar onto the page or off the window to tear it off into a little window, live page and all; drag a little window by its toolbar over the sidebar to dock it back
- On a Force Touch trackpad, quiet haptic detents mark the moments that click into place: the sidebar snapping shut or open and reaching its width limits, the split divider snapping to center, a dragged tab changing where it will land, a swipe passing the point where it commits, and a tab tearing off or docking
- Each space has a color (Space > Space Color, or right-click its button) that lightly tints the sidebar and colors the selected row, focus ring and loading line; the page's theme color blends on top
- Split view: two tabs side by side with a draggable divider, shown as one joined row in the sidebar
- Command bar for URLs, search (with Google suggestions) and switching tabs
- Paste a list of links (like Safari's Copy Links) into the command bar to open them all as tabs that load when you select them; ⌘Return opens them in the background, ⌥Return nests them under the first
- Built-in ad and tracker blocking (uBlock Origin, EasyList and EasyPrivacy lists)
- Fill logins from Apple Passwords through a native card with Touch ID
- Native permission prompts for camera, microphone, location and the rest
- Session restore with lazy tabs, so launch stays fast
- History per space: recent pages in the History menu, a searchable History window (⌘Y), and frecency-ranked matches in the command bar
- Tabs left unselected for 12 hours archive themselves (they fade gently from 6 hours on, back to full on hover); find them again in the command bar
- Downloads progress in the sidebar; click to cancel, or to show the file in Finder
- A crashed page shows a Reload button instead of a blank tab
- Web notifications appear as macOS notifications after you allow them for a site (View > Allow Notifications from This Site turns them on or off); clicking one returns you to its tab
- A Now Playing row with the track's artwork (or the video poster, or the site icon), softly tinted to match, and play/pause for the tab that last started audio; a speaker icon on playing tabs mutes them
- A one-line weather row at the bottom of the sidebar (Open-Meteo, city-level location; hover for the 7-day forecast, click to search the weather)
- Fullscreen video fills the whole screen; the sidebar and page card come back when it ends
- View > Clear Data for This Site deletes that site's cookies and storage in the current space
- Native right-click menus on pages: links, images, selections, spelling suggestions, Inspect Element
- Hovering a link shows its address in a small bubble at the bottom of the page
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

## Proprietary codecs (local builds only)

The stock CEF build plays VP8, VP9, AV1, Opus and other open formats, but not H.264, AAC or MP4. Those formats are covered by patent pools (Via LA for H.264 and AAC), and Chromium only compiles their decoders with `proprietary_codecs=true ffmpeg_branding=Chrome`. Google licenses them for Chrome; a CEF built with them and handed to other people needs its own license. So released builds always use the stock CEF, and the codecs build stays on your own machine.

`scripts/build-cef-codecs.sh` builds CEF from source with the codecs (about three hours on an M5 and about 55 GB of free disk at its peak; the 32 GB Chromium checkout is kept for rebuilds) and installs it to `~/.local/share/cef/156.0.14-codecs/cef_macos_aarch64`. Once that folder exists, `make` and `make install` use it automatically; `MINI_CEF_CODECS=0 make` builds with the stock CEF. `make release` always uses the stock CEF and refuses to publish if the bundled framework has the codecs.

## Keyboard

| Shortcut | Action |
| --- | --- |
| ⌘T | New tab (command bar) |
| ⌥⌘T | New child tab |
| ⌘L | Edit the current address |
| ⌘O | Move the page in a little window into a tab |
| ⌘W | Close tab (pinned and saved tabs reset to their page instead) |
| ⇧⌘T | Reopen closed tab |
| ⌘Z, ⇧⌘Z | Undo and redo tab actions: close (a whole group comes back in place), move, nest, pin, save, split, duplicate, opening pasted links. In a text field or editable page area they undo typing instead |
| ⌃Tab, ⌃⇧Tab, ⌥⌘↓, ⌥⌘↑ | Next and previous tab |
| ⌘1 to ⌘9 | Select tab (pinned first; ⌘9 is the last) |
| ⌃1 to ⌃9 | Switch space |
| ⌥⌘→, ⌥⌘← | Indent and outdent |
| ⌥⌘\ | Collapse or expand a group |
| ⌃⌘P | Pin or unpin tab |
| ⌘D | Save or unsave tab |
| ⇧⌘D | Duplicate tab (opens right below it) |
| ⌃⇧↑, ⌃⇧↓ | Move the tab up or down among its siblings |
| ⌃⌘S | Show or hide the sidebar |
| ⌃⌘\ | Split the current tab with the last one you used, or close the split |
| ⌘\ | Fill password |
| ⇧⌘C | Copy the page address |
| ⌘Y | Show all history |
| ⌘[, ⌘] | Back and forward (right-click or hold the arrow buttons for the history list) |
| ⌘R, ⌘. | Reload and stop |
| ⌘F, ⌘G, ⇧⌘G | Find, next, previous |
| ⌘=, ⌘-, ⌘0 | Zoom in, out, actual size (remembered per site) |
| ⌘P | Print the page |
| ⌥⌘P | Picture in picture for the largest playing video |
| ⌥⌘I | Developer tools |

In the sidebar: click its empty space (or press Tab when nothing has focus) to move the keyboard there. ↑ and ↓ move between pinned tabs and rows, ← and → collapse or expand a group (or go to its parent or first child), Return opens the tab, Delete closes it, and Esc or Tab returns to the page.

Browser shortcuts take priority over the page, so ⌘T or ⌘W work even when a site tries to capture them. Copy, paste and select all always go to the page; ⌘Z and ⇧⌘Z go to the page while a text field or other editable element there has focus, and undo tab actions otherwise.

## Passwords

When a page has a login form, a key button appears in the address pill. Click it or press ⌘\ and Mini shows a small card with the site's address and two native fields. Click the key icon in the password field, pick a login from Apple Passwords, confirm with Touch ID, and press Return to fill the page. Mini never shows the card on its own and never stores or logs the values.

macOS does not know which website Mini is showing, so it lists all your logins instead of suggesting the matching one. Site-matched suggestions and passkeys need Apple's macOS Web Browser Public Key Credential entitlement, which has to be requested from Apple.

Passkeys are not supported until that entitlement is granted. Mini turns off WebAuthn in pages (passkey requests fail as "not allowed" and platform authenticators report unavailable), so sites fall back to passwords and Chromium never shows its QR code or "use your phone" dialog.

## Where things live

- `~/Library/Application Support/Mini/Profile`: cookies, cache and site data of the Personal space (the first space, which keeps the profile Mini always used)
- `~/Library/Application Support/Mini/Profile/Spaces/<id>`: cookies, cache and site data of every other space; deleting a space removes its folder
- `~/Library/Application Support/Mini/session.json`: spaces and their open tabs
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

- One main window. The Personal space cannot be deleted, because it holds the original profile. Little windows for outside links deny permission and HTTP sign-in prompts unless the site was already allowed; open the page in Mini to answer them.
- Web notifications only work while the page is open: Mini replaces the page's `Notification` API and `showNotification` with native macOS notifications, but a service worker cannot show notifications on its own, so push notifications for closed tabs never arrive.
- Google sometimes refuses sign-in from embedded Chromium with "This browser or app may not be secure".

## License

MIT
