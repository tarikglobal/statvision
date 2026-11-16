#!/bin/bash
set -euo pipefail
statvision_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$statvision_root"
mkdir -p build
xcrun swiftc -parse-as-library statvision/Metrics/*.swift statvision/Design/EyeArtwork.swift scripts/generate-icon.swift -o build/GenerateIcon
build/GenerateIcon
iconutil -c icns build/AppIcon.iconset -o statvision/Resources/AppIcon.icns
