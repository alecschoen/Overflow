#!/bin/bash
# Rebuilds SupportFiles/AppIcon.icns from SupportFiles/AppIcon-source.png.
# Needs only macOS built-ins (sips + iconutil).
set -euo pipefail
cd "$(dirname "$0")/.."

SOURCE="SupportFiles/AppIcon-source.png"
ICONSET="build/AppIcon.iconset"

rm -rf "$ICONSET"
mkdir -p "$ICONSET"

# Normalize to a 1024x1024 master first.
sips -z 1024 1024 "$SOURCE" --out "$ICONSET/icon_512x512@2x.png" >/dev/null

for size in 16 32 128 256 512; do
    sips -z $size $size "$ICONSET/icon_512x512@2x.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z $double $double "$ICONSET/icon_512x512@2x.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done

iconutil -c icns "$ICONSET" -o SupportFiles/AppIcon.icns
echo "Wrote SupportFiles/AppIcon.icns"
