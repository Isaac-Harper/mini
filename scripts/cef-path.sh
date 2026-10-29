#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cef_version="$(awk '/^name = "cef-dll-sys"$/ { getline; split($0, parts, "\""); print parts[2] }' "$repository_root/core/Cargo.lock")"
cef_version="${cef_version#*+}"
codecs_directory="$HOME/.local/share/cef/$cef_version-codecs/cef_macos_aarch64"
if [[ "${MINI_CEF_CODECS:-1}" != "0" && -f "$codecs_directory/archive.json" ]]; then
  echo "$codecs_directory"
else
  echo "$HOME/.local/share/cef"
fi
