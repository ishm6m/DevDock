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
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
  build

APP="$PRODUCT_DIR/${APP_NAME}.app"
if [[ ! -d "$APP" ]]; then
  echo "error: build did not produce $APP" >&2
  exit 1
fi

# Ad-hoc signing is deliberate (no paid Developer ID), but Hardened Runtime and
# the entitlements must survive it: they are prerequisites for notarization, so
# keeping them on now means enabling notarization later is a credentials change
# rather than a code change. Fail loudly if a build setting ever drops them.
echo "==> Verifying signing invariants"
SIG_INFO="$(codesign -dv --entitlements :- "$APP" 2>&1)"

if ! grep -q 'flags=.*runtime' <<<"$SIG_INFO"; then
  echo "error: Hardened Runtime is missing from the signature." >&2
  echo "       Expected ENABLE_HARDENED_RUNTIME=YES (set in project.yml)." >&2
  exit 1
fi

# The app is intentionally not sandboxed; it inspects and signals other
# processes. Confirm the entitlement is present and explicitly false.
if ! grep -q 'com.apple.security.app-sandbox' <<<"$SIG_INFO"; then
  echo "error: entitlements were not applied to the built app." >&2
  echo "       Expected CODE_SIGN_ENTITLEMENTS to point at DevDock.entitlements." >&2
  exit 1
fi

# Xcode injects com.apple.security.get-task-allow when signing with a
# development-style identity (and "-" counts as one). In a shipped build it lets
# any local process attach a debugger to DevDock, which undoes much of what
# Hardened Runtime buys — and notarization rejects it outright. Suppressed above
# via CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO; verified here.
if grep -q 'get-task-allow' <<<"$SIG_INFO"; then
  echo "error: the release build carries the get-task-allow debug entitlement." >&2
  echo "       Expected CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO on the build." >&2
  exit 1
fi

echo "    Hardened Runtime: on"
echo "    Entitlements:     applied"
echo "    Debug entitlement: absent"

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
