#!/bin/bash
# Builds Overflow.app from the SwiftPM package and signs it.
#
# Works with just the Command Line Tools (no full Xcode needed).
#
# Usage:
#   Scripts/build-app.sh                    # release build, ad-hoc signed
#   CONFIGURATION=debug Scripts/build-app.sh
#   CODESIGN_IDENTITY="DisplayVolume Dev" Scripts/build-app.sh
#
# IMPORTANT: macOS ties privacy permissions (Screen Recording,
# Accessibility) to the code signature + bundle ID. Ad-hoc signatures change
# on every build, which makes macOS treat each build as a new app and re-ask
# for permissions. For day-to-day use, sign with a stable identity (set
# CODESIGN_IDENTITY) so permissions stick across rebuilds.

set -euo pipefail
cd "$(dirname "$0")/.."

CONFIGURATION="${CONFIGURATION:-release}"
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:--}"

if [[ "$CODESIGN_IDENTITY" != "-" ]]; then
    if ! security find-identity -v -p codesigning | grep -qF "$CODESIGN_IDENTITY"; then
        echo "error: no code-signing identity named \"$CODESIGN_IDENTITY\" in your keychain." >&2
        echo "       List identities with: security find-identity -v -p codesigning" >&2
        exit 1
    fi
fi

APP_NAME="Overflow"
OUT_DIR="${OUT_DIR:-build}"
APP_BUNDLE="$OUT_DIR/$APP_NAME.app"

echo "==> swift build -c $CONFIGURATION"
swift build -c "$CONFIGURATION"

BIN_PATH="$(swift build -c "$CONFIGURATION" --show-bin-path)/OverflowApp"
if [[ ! -f "$BIN_PATH" ]]; then
    echo "error: built binary not found at $BIN_PATH" >&2
    exit 1
fi

echo "==> Assembling $APP_BUNDLE"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
cp "$BIN_PATH" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp SupportFiles/Info.plist "$APP_BUNDLE/Contents/Info.plist"
cp SupportFiles/AppIcon.icns "$APP_BUNDLE/Contents/Resources/"
printf 'APPL????' > "$APP_BUNDLE/Contents/PkgInfo"

echo "==> Signing (identity: $CODESIGN_IDENTITY)"
codesign --force --sign "$CODESIGN_IDENTITY" \
    --entitlements SupportFiles/Overflow.entitlements \
    --options runtime \
    "$APP_BUNDLE" 2>/dev/null || \
codesign --force --sign "$CODESIGN_IDENTITY" \
    --entitlements SupportFiles/Overflow.entitlements \
    "$APP_BUNDLE"

codesign --verify --verbose=2 "$APP_BUNDLE"

echo
echo "Built: $APP_BUNDLE"
echo "Install: rm -rf /Applications/$APP_NAME.app && cp -R \"$APP_BUNDLE\" /Applications/"
