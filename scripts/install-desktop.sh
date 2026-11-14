#!/bin/bash
set -euo pipefail

statvision_root="$(cd "$(dirname "$0")/.." && pwd)"
statvision_source="$statvision_root/build/Build/Products/Release/statvision.app"
statvision_archive="$statvision_root/build/Distribution/statvision-macOS-universal.zip"
statvision_desktop_app="$HOME/Desktop/statvision.app"
statvision_desktop_zip="$HOME/Desktop/statvision-paylasim.zip"

if [[ ! -f "$statvision_source/Contents/MacOS/statvision" || ! -f "$statvision_archive" ]]; then
  printf 'Build the Release app and ZIP with bash scripts/package-release.sh first.\n' >&2
  exit 1
fi
if [[ -e "$statvision_desktop_app" || -L "$statvision_desktop_app" || -e "$statvision_desktop_zip" ]]; then
  printf 'Desktop destination already exists; no files were replaced.\n' >&2
  exit 1
fi

ditto "$statvision_source" "$statvision_desktop_app"
ditto "$statvision_archive" "$statvision_desktop_zip"
codesign --verify --deep --strict "$statvision_desktop_app"

# Relaunch this app only, so Finder does not reuse an older Debug process.
if pgrep -x statvision >/dev/null; then
  pkill -TERM -x statvision
  for statvision_attempt in 1 2 3 4 5 6 7 8 9 10; do
    if ! pgrep -x statvision >/dev/null; then break; fi
    sleep 0.2
  done
  if pgrep -x statvision >/dev/null; then
    printf 'statvision is still running; quit it and open the Desktop app.\n' >&2
    exit 1
  fi
fi
open "$statvision_desktop_app"
printf 'Desktop app: %s\nSharing ZIP: %s\n' "$statvision_desktop_app" "$statvision_desktop_zip"
