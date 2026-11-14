#!/bin/bash
set -euo pipefail

statvision_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$statvision_root"

if [[ ! -f statvision/Resources/AppIcon.icns ]]; then
  printf 'Missing AppIcon.icns; run scripts/generate-icon.swift and iconutil first.\n' >&2
  exit 1
fi

xcodebuild -project statvision.xcodeproj -scheme statvision \
  -configuration Release -destination 'generic/platform=macOS' \
  -derivedDataPath build ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO build

statvision_app="$statvision_root/build/Build/Products/Release/statvision.app"
statvision_distribution="$statvision_root/build/Distribution"
mkdir -p "$statvision_distribution"

# Fail if either architecture is missing or the bundle's signature is invalid.
lipo "$statvision_app/Contents/MacOS/statvision" -verify_arch arm64
lipo "$statvision_app/Contents/MacOS/statvision" -verify_arch x86_64
codesign --verify --deep --strict "$statvision_app"
ditto -c -k --sequesterRsrc --keepParent "$statvision_app" \
  "$statvision_distribution/statvision-macOS-universal.zip"
shasum -a 256 "$statvision_distribution/statvision-macOS-universal.zip"
printf '\nApp: %s\nZIP: %s\n' "$statvision_app" \
  "$statvision_distribution/statvision-macOS-universal.zip"
