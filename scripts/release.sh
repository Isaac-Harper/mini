#!/usr/bin/env bash
set -euo pipefail

version="${1:?usage: scripts/release.sh <version>, for example scripts/release.sh 0.1.0}"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Version must be X.Y.Z without a leading v." >&2; exit 1; }
repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
notary_profile="${MINI_NOTARY_PROFILE:-lowlight-notary}"
app="$repository_root/build/Mini.app"
dist="$repository_root/dist"
zip="$dist/Mini-$version-arm64.zip"
cd "$repository_root"

identity="$(security find-identity -v -p codesigning | grep -o '"Developer ID Application: [^"]*"' | head -1 | tr -d '"' || true)"
[[ -n "$identity" ]] || { echo "No Developer ID Application certificate in the keychain." >&2; exit 1; }
xcrun notarytool history --keychain-profile "$notary_profile" >/dev/null 2>&1 \
  || { echo "No notary credentials saved as '$notary_profile'." >&2; exit 1; }
[[ -z "$(git status --porcelain)" ]] || { echo "Commit or stash changes first." >&2; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "gh is not logged in." >&2; exit 1; }
git fetch -q --tags origin
! git rev-parse -q --verify "refs/tags/v$version" >/dev/null || { echo "Tag v$version already exists." >&2; exit 1; }
[[ "$(git rev-parse HEAD)" == "$(git rev-parse '@{u}')" ]] || { echo "Push HEAD first." >&2; exit 1; }
plist_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' bundle/Info.plist)"
[[ "$plist_version" == "$version" ]] || { echo "bundle/Info.plist says $plist_version, not $version." >&2; exit 1; }

MINI_SIGN_IDENTITY="$identity" MINI_TIMESTAMP=1 CONFIG=release scripts/bundle.sh
codesign --verify --deep --strict --verbose=2 "$app"

echo "==> Notarizing"
mkdir -p "$dist"
rm -f "$zip"
ditto -c -k --keepParent "$app" "$zip"
xcrun notarytool submit "$zip" --keychain-profile "$notary_profile" --wait
xcrun stapler staple "$app"
spctl -a -vv "$app"
rm -f "$zip"
ditto -c -k --keepParent "$app" "$zip"

echo "==> Publishing v$version"
notes="Mini is an open source exploration project: a personal, minimal macOS browser built to explore a native Swift shell over Chromium (CEF).

- Apple Silicon, macOS 26 or later
- Signed with Developer ID and notarized by Apple
- No auto-update; download new releases from this page"
gh release create "v$version" "$zip" --target "$(git rev-parse HEAD)" --title "Mini $version" --notes "$notes"
git fetch -q --tags origin
gh release view "v$version" --json url,assets --jq '.url, .assets[].url'
