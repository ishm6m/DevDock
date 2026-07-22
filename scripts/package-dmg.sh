#!/usr/bin/env bash
#
# Build DevDock (Release, ad-hoc signed) and package it into a distributable .dmg.
#
# No Apple Developer account required — the app is ad-hoc signed ("Sign to Run
# Locally"), which is enough to run on any Mac after the user clears the
# quarantine flag (`xattr -dr com.apple.quarantine`, or System Settings →
# Privacy & Security → "Open Anyway"). Note that an ad-hoc build always trips
# Gatekeeper on download; only Developer ID signing + notarization avoids it.
# Sparkle auto-update stays dormant (Info.plist ships placeholders) until a
# maintainer configures release credentials.
#
# Usage:
#   scripts/package-dmg.sh [version]
#
# `version` defaults to MARKETING_VERSION in project.yml. Output: DevDock-<version>.dmg
# in the repo root.
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="DevDock"
DERIVED="build/dd"
PRODUCT_DIR="$DERIVED/Build/Products/Release"

VERSION="${1:-$(grep -m1 'MARKETING_VERSION' project.yml | sed -E 's/.*"([0-9.]+)".*/\1/')}"
if [[ -z "$VERSION" ]]; then
  echo "error: could not determine version (pass it as an argument)" >&2
  exit 1
fi
DMG="${APP_NAME}-${VERSION}.dmg"

echo "==> Generating Xcode project"
xcodegen generate

echo "==> Building ${APP_NAME} ${VERSION} (Release, ad-hoc signed)"
xcodebuild \
  -project "${APP_NAME}.xcodeproj" \
  -scheme "${APP_NAME}" \
  -configuration Release \
  -derivedDataPath "$DERIVED" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="-" \
  DEVELOPMENT_TEAM="" \
  build

APP="$PRODUCT_DIR/${APP_NAME}.app"
if [[ ! -d "$APP" ]]; then
  echo "error: build did not produce $APP" >&2
  exit 1
fi

echo "==> Staging disk image contents"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

echo "==> Creating $DMG"
rm -f "$DMG"
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGE" \
  -ov -format UDZO \
  "$DMG"

echo "==> Done: $DMG"
codesign -dv "$APP" 2>&1 | grep -i 'Signature' || true
