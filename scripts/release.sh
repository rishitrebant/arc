#!/bin/bash
#
# Builds the DMG, generates the Sparkle appcast, and publishes both as a
# GitHub Release on rishitrebant/arc. Installed copies of ARC pick it up
# through the feed URL in Config/Info-Extra.plist.
#
#   ./scripts/release.sh
#
# Before running:
#   1. Bump MARKETING_VERSION (a new number every release — the git tag
#      and the GitHub release are named after it) AND CURRENT_PROJECT_VERSION.
#
#      CURRENT_PROJECT_VERSION is the one Sparkle actually compares: an
#      installed copy is offered an update only when the new build NUMBER
#      is higher than its own. It must go up on every release, always —
#      lowering it (or resetting it to 1) makes Sparkle say "You're up to
#      date" to everyone on an older build, even though the version name
#      looks newer. This script refuses to publish if it isn't higher than
#      the build number of the release currently published.
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

# ── Safety checks: these are what let people actually update ──────────────

PBXPROJ="Island.xcodeproj/project.pbxproj"

VERSION=$(sed -n 's/.*MARKETING_VERSION = \(.*\);/\1/p' "$PBXPROJ" | head -1)
BUILD=$(sed -n 's/.*CURRENT_PROJECT_VERSION = \(.*\);/\1/p' "$PBXPROJ" | head -1)
TAG="v$VERSION"

[[ "$BUILD" =~ ^[0-9]+$ ]] || { echo "CURRENT_PROJECT_VERSION ($BUILD) must be a whole number"; exit 1; }

# A release with this tag already exists: the version name wasn't bumped.
if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
    echo "✗ $TAG is already released. Bump MARKETING_VERSION (and CURRENT_PROJECT_VERSION)."
    exit 1
fi

# The build number of what's published now, read from its appcast.
PUBLISHED_BUILD=$(curl -fsSL "https://github.com/$REPO/releases/latest/download/appcast.xml" 2>/dev/null \
    | grep -oE 'sparkle:version(>|=")[0-9]+' | grep -oE '[0-9]+$' | sort -n | tail -1 || true)

if [ -n "$PUBLISHED_BUILD" ] && [ "$BUILD" -le "$PUBLISHED_BUILD" ]; then
    echo "✗ Build number $BUILD is not higher than the published build ($PUBLISHED_BUILD)."
    echo "  Installed copies would be told they're up to date. Raise CURRENT_PROJECT_VERSION and retry."
    exit 1
fi

if ! git diff --quiet HEAD -- . 2>/dev/null; then
    echo "⚠ You have uncommitted changes — they will be in this release but not in git."
fi

echo "▸ Releasing ARC $VERSION (build $BUILD)${PUBLISHED_BUILD:+, replacing build $PUBLISHED_BUILD}"

./scripts/make-dmg.sh

DMG="dist/ARC-$VERSION.dmg"
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
