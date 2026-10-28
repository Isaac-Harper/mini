#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
config="${CONFIG:-release}"
export CEF_PATH="${CEF_PATH:-$HOME/.local/share/cef}"
default_sign_identity="$(security find-identity -v -p codesigning | awk -F'"' '/Developer ID Application|Apple Development/ { print $2; exit }')"
sign_identity="${MINI_SIGN_IDENTITY:-${default_sign_identity:--}}"
if [[ "$sign_identity" == "-" ]]; then
  echo "warning: no signing identity found, signing ad hoc. Every rebuild will ask for Keychain access again." >&2
fi
skip_shell="${SKIP_SHELL:-0}"

case "$config" in
  release) cargo_profile_flag=(--release) ;;
  debug) cargo_profile_flag=() ;;
  *) echo "CONFIG must be release or debug, got '$config'" >&2; exit 1 ;;
esac

echo "==> Building Rust core ($config)"
(cd "$repository_root/core" && cargo build "${cargo_profile_flag[@]+"${cargo_profile_flag[@]}"}")
helper_binary="$repository_root/core/target/$config/mini-helper"

cef_version="$(awk '/^name = "cef-dll-sys"$/ { getline; split($0, parts, "\""); print parts[2] }' "$repository_root/core/Cargo.lock")"
cef_version="${cef_version#*+}"
cef_directory="$CEF_PATH/$cef_version/cef_macos_aarch64"
framework_source="$cef_directory/Chromium Embedded Framework.framework"
if [[ ! -d "$framework_source" ]]; then
  echo "CEF framework not found at $framework_source" >&2
  exit 1
fi

main_binary=""
if [[ "$skip_shell" == "1" ]]; then
  echo "==> Skipping Swift shell (SKIP_SHELL=1)"
else
  echo "==> Building Swift shell ($config)"
  (cd "$repository_root/shell" && swift build -c "$config")
  main_binary="$(cd "$repository_root/shell" && swift build -c "$config" --show-bin-path)/Mini"
fi

app="$repository_root/build/Mini.app"
contents="$app/Contents"
frameworks="$contents/Frameworks"
echo "==> Assembling $app"
rm -rf "$app"
mkdir -p "$contents/MacOS" "$contents/Resources" "$frameworks"
cp "$repository_root/bundle/Info.plist" "$contents/Info.plist"
if [[ -n "$main_binary" ]]; then
  cp "$main_binary" "$contents/MacOS/Mini"
fi
if [[ -d "$repository_root/shell/Resources" ]] && [[ -n "$(ls -A "$repository_root/shell/Resources")" ]]; then
  cp -R "$repository_root/shell/Resources/." "$contents/Resources/"
fi
ditto "$framework_source" "$frameworks/Chromium Embedded Framework.framework"

write_helper_plist() {
  local plist_path="$1" executable_name="$2" identifier="$3"
  cat > "$plist_path" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleDisplayName</key>
	<string>$executable_name</string>
	<key>CFBundleExecutable</key>
	<string>$executable_name</string>
	<key>CFBundleIdentifier</key>
	<string>$identifier</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>$executable_name</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>0.1.0</string>
	<key>CFBundleSignature</key>
	<string>????</string>
	<key>CFBundleVersion</key>
	<string>0.1.0</string>
	<key>LSEnvironment</key>
	<dict>
		<key>MallocNanoZone</key>
		<string>0</string>
	</dict>
	<key>LSFileQuarantineEnabled</key>
	<true/>
	<key>LSMinimumSystemVersion</key>
	<string>26.0</string>
	<key>LSUIElement</key>
	<string>1</string>
	<key>NSBluetoothAlwaysUsageDescription</key>
	<string>$executable_name</string>
	<key>NSCameraUsageDescription</key>
	<string>$executable_name</string>
	<key>NSMicrophoneUsageDescription</key>
	<string>$executable_name</string>
	<key>NSSupportsAutomaticGraphicsSwitching</key>
	<true/>
	<key>NSWebBrowserPublicKeyCredentialUsageDescription</key>
	<string>$executable_name</string>
</dict>
</plist>
PLIST
}

helper_apps=()
for helper_kind in "" "GPU" "Renderer" "Plugin" "Alerts"; do
  if [[ -z "$helper_kind" ]]; then
    helper_name="Mini Helper"
    helper_identifier="dev.isaacharper.mini.helper"
  else
    helper_name="Mini Helper ($helper_kind)"
    helper_identifier="dev.isaacharper.mini.helper.$(echo "$helper_kind" | tr '[:upper:]' '[:lower:]')"
  fi
  helper_app="$frameworks/$helper_name.app"
  mkdir -p "$helper_app/Contents/MacOS"
  cp "$helper_binary" "$helper_app/Contents/MacOS/$helper_name"
  write_helper_plist "$helper_app/Contents/Info.plist" "$helper_name" "$helper_identifier"
  helper_apps+=("$helper_app")
done

echo "==> Signing with identity '$sign_identity'"
sign() {
  codesign --force --sign "$sign_identity" "$@"
}
framework="$frameworks/Chromium Embedded Framework.framework"
for library in "$framework/Libraries/"*.dylib; do
  sign "$library"
done
sign "$framework"
for helper_app in "${helper_apps[@]}"; do
  sign "$helper_app"
done
if [[ -f "$contents/MacOS/Mini" ]]; then
  sign "$app"
else
  echo "==> No main executable; skipping signing of Mini.app itself"
fi

echo "==> Built $app"
