#!/usr/bin/env bash
set -euo pipefail

cef_commit=4fa4ab516dacf6c49fc7e6e70d2b7ebce29fa35f
cef_branch=8078
cef_version=156.0.14
work="${CEF_BUILD_DIRECTORY:-$HOME/code/cef-build}"
destination="$HOME/.local/share/cef/$cef_version-codecs/cef_macos_aarch64"
export GN_DEFINES="is_official_build=true proprietary_codecs=true ffmpeg_branding=Chrome symbol_level=0 chrome_pgo_phase=0"

mkdir -p "$work"
cd "$work"
curl -fsSL -o automate-git.py "https://raw.githubusercontent.com/chromiumembedded/cef/$cef_commit/tools/automate/automate-git.py"
arguments=(
  --download-dir="$work/chromium_git"
  --depot-tools-dir="$work/depot_tools"
  --branch="$cef_branch"
  --checkout="$cef_commit"
  --arm64-build
  --no-debug-build
  --no-chromium-history
  --minimal-distrib
  --no-distrib-docs
  --no-distrib-symbols
  --no-distrib-archive
  # make_distrib.py on macOS takes the framework from cefclient.app; with only cefsimple built it packages no Release files.
  --build-target=cefclient
)
built=0
for attempt in 1 2 3; do
  echo "==> automate-git.py attempt $attempt"
  if caffeinate -is nice -n 10 python3 automate-git.py "${arguments[@]}"; then
    built=1
    break
  fi
  sleep 60
done
[[ "$built" == "1" ]] || { echo "CEF build failed three times" >&2; exit 1; }

distribs=("$work/chromium_git/chromium/src/cef/binary_distrib/cef_binary_$cef_version+g${cef_commit:0:7}+chromium-"*"_macosarm64_minimal")
[[ ${#distribs[@]} -eq 1 && -d "${distribs[0]}/Release/Chromium Embedded Framework.framework" ]] \
  || { echo "Expected one minimal distribution, found: ${distribs[*]}" >&2; exit 1; }
distrib="${distribs[0]}"

echo "==> Installing $distrib to $destination"
staging="$destination.partial"
rm -rf "$staging"
mkdir -p "$staging"
ditto "$distrib/Release" "$staging"
for item in CMakeLists.txt cmake include libcef_dll CREDITS.html; do
  ditto "$distrib/$item" "$staging/$item"
done
printf 'GN_DEFINES=%s\nCEF commit %s\n' "$GN_DEFINES" "$cef_commit" > "$staging/Chromium Embedded Framework.framework/Resources/proprietary_codecs.txt"
printf '{\n  "type": "minimal",\n  "name": "%s.tar.bz2",\n  "sha1": ""\n}\n' "$(basename "$distrib")" > "$staging/archive.json"
rm -rf "$destination"
mv "$staging" "$destination"

echo "==> Removing build output"
rm -rf "$work/chromium_git/chromium/src/out"
free_gigabytes="$(df -g / | awk 'NR == 2 { print $4 }')"
if (( free_gigabytes < 40 )); then
  echo "==> Only ${free_gigabytes} GB free, removing the Chromium checkout"
  rm -rf "$work/chromium_git/chromium"
else
  echo "==> Kept the Chromium checkout ($(du -sh "$work/chromium_git" | cut -f1)) for rebuilds"
fi
echo "==> Installed $destination"
