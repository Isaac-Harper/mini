#!/usr/bin/env bash
set -euo pipefail

app="${1:?usage: scripts/check-stock-cef.sh <path to Mini.app>}"
framework="$app/Contents/Frameworks/Chromium Embedded Framework.framework"
binary="$framework/Chromium Embedded Framework"
[[ -f "$binary" ]] || { echo "No CEF framework binary at $binary" >&2; exit 1; }

if [[ -e "$framework/Resources/proprietary_codecs.txt" ]]; then
  echo "Refusing: $framework is the proprietary codecs build (marker file present)." >&2
  exit 1
fi
if LC_ALL=C grep -q -a -F "Creating H264DecoderImpl." "$binary"; then
  echo "Refusing: $binary contains the H.264 decoder." >&2
  exit 1
fi
echo "==> CEF framework is the stock build"
