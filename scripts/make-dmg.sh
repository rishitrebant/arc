#!/bin/bash
#
# Builds ARC in Release and packages it as dist/ARC-<version>.dmg
# (ARC.app + an Applications shortcut + a short "Read Me First").
#
#   ./scripts/make-dmg.sh
#
# Optional, for a build you can hand to other people without Gatekeeper
# warnings (needs a paid Apple Developer account):
#
#   SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
#   NOTARY_PROFILE="arc-notary" \
#   ./scripts/make-dmg.sh
#
# SIGN_IDENTITY   re-signs ARC.app with the hardened runtime + the
#                 entitlements in scripts/ARC.entitlements
# NOTARY_PROFILE  a profile saved with:
#                 xcrun notarytool store-credentials arc-notary
#                 (the DMG is submitted, waited on, and stapled)

set -euo pipefail

cd "$(dirname "$0")/.."

BUILD_DIR="$(mktemp -d)/build"
STAGE_DIR="$(mktemp -d)/ARC"
mkdir -p "$STAGE_DIR" dist

echo "▸ Building ARC (Release)…"
xcodebuild \
    -project Island.xcodeproj \
    -scheme Island \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR" \
    build | tail -1

APP="$BUILD_DIR/Build/Products/Release/ARC.app"
[ -d "$APP" ] || { echo "ARC.app was not produced"; exit 1; }

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
DMG="dist/ARC-$VERSION.dmg"

if [ -n "${SIGN_IDENTITY:-}" ]; then
    echo "▸ Signing with: $SIGN_IDENTITY"
    codesign --force --deep --options runtime --timestamp \
        --entitlements scripts/ARC.entitlements \
        --sign "$SIGN_IDENTITY" "$APP"
    codesign --verify --deep --strict "$APP"
fi

echo "▸ Staging…"
cp -R "$APP" "$STAGE_DIR/"
ln -s /Applications "$STAGE_DIR/Applications"

cat > "$STAGE_DIR/Read Me First.txt" <<'TXT'
ARC — the notch, extended.

INSTALL
  Drag ARC into the Applications folder, then open it from there.

FIRST OPEN
  If macOS says it can't verify the developer, right-click ARC in
  Applications, choose Open, then click Open. If it says the app is
  damaged, run this once in Terminal and open it again:
    xattr -dr com.apple.quarantine /Applications/ARC.app

PERMISSIONS
  macOS asks the first time a feature needs one: Bluetooth, Calendars,
  Downloads folder, Automation (Music / Spotify) and Focus.

REQUIRES  a MacBook with a notch, macOS 14 or later.
TXT

echo "▸ Creating ${DMG}…"
rm -f "$DMG"
hdiutil create -volname "ARC" -srcfolder "$STAGE_DIR" -format UDZO -ov "$DMG" >/dev/null

if [ -n "${SIGN_IDENTITY:-}" ]; then
    codesign --force --sign "$SIGN_IDENTITY" "$DMG"
fi

if [ -n "${NOTARY_PROFILE:-}" ]; then
    echo "▸ Notarizing (this can take a few minutes)…"
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG"
fi

echo "✓ $DMG"
shasum -a 256 "$DMG"
