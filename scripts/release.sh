#!/bin/bash
#
# Builds the DMG, generates the Sparkle appcast, and publishes both as a
# GitHub Release on rishitrebant/arc. Installed copies of ARC pick it up
# through the feed URL in Config/Info-Extra.plist.
#
#   ./scripts/release.sh
#
# Before running:
#   1. Bump MARKETING_VERSION and CURRENT_PROJECT_VERSION (the build
#      number must go up every release — Sparkle compares it).
#   2. Commit and push.
#
# Needs: the `gh` CLI (gh auth login), and Sparkle's `generate_appcast`
# (found automatically once Xcode has fetched the Sparkle package, or set
# SPARKLE_BIN to the folder containing it). The signing key made by
# `generate_keys` must be in your login Keychain.
#
# RELEASE_NOTES="Fixed X" ./scripts/release.sh   adds notes to the release.

set -euo pipefail

cd "$(dirname "$0")/.."

REPO="rishitrebant/arc"

command -v gh >/dev/null || { echo "Install the GitHub CLI first: brew install gh"; exit 1; }

# Locate generate_appcast.
GENERATE_APPCAST=""
if [ -n "${SPARKLE_BIN:-}" ] && [ -x "$SPARKLE_BIN/generate_appcast" ]; then
    GENERATE_APPCAST="$SPARKLE_BIN/generate_appcast"
elif command -v generate_appcast >/dev/null; then
    GENERATE_APPCAST="$(command -v generate_appcast)"
else
    GENERATE_APPCAST=$(find ~/Library/Developer/Xcode/DerivedData \
        -path "*artifacts/sparkle/Sparkle/bin/generate_appcast" 2>/dev/null | head -1)
fi
[ -x "$GENERATE_APPCAST" ] || { echo "generate_appcast not found — set SPARKLE_BIN"; exit 1; }

./scripts/make-dmg.sh

VERSION=$(sed -n 's/.*MARKETING_VERSION = \(.*\);/\1/p' Island.xcodeproj/project.pbxproj | head -1)
DMG="dist/ARC-$VERSION.dmg"
TAG="v$VERSION"
[ -f "$DMG" ] || { echo "$DMG not found"; exit 1; }

# The appcast only needs the newest version, so it's built from a folder
# holding just this DMG. That also lets the download prefix match this tag.
UPDATES_DIR="$(mktemp -d)"
cp "$DMG" "$UPDATES_DIR/"

echo "▸ Generating appcast…"
"$GENERATE_APPCAST" \
    --download-url-prefix "https://github.com/$REPO/releases/download/$TAG/" \
    "$UPDATES_DIR"

echo "▸ Publishing $TAG to GitHub…"
gh release create "$TAG" \
    "$DMG" "$UPDATES_DIR/appcast.xml" \
    --repo "$REPO" \
    --title "ARC $VERSION" \
    --notes "${RELEASE_NOTES:-ARC $VERSION}"

echo "✓ Released $TAG — installed copies will see it on their next check."
