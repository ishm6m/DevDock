#!/usr/bin/env bash
#
# Install the latest DevDock release into /Applications.
#
#   curl -fsSL https://raw.githubusercontent.com/ishm6m/DevDock/main/scripts/install.sh | bash
#
# Why this exists: DevDock is ad-hoc signed, not notarized, so a browser download
# trips Gatekeeper ("Apple could not verify..."). Browsers are what attach the
# com.apple.quarantine flag that triggers that check — curl does not. Installing
# this way is warning-free, and the `xattr -d` below is only belt-and-braces for
# the case where a download tool did stamp the file.
#
# Usage:
#   install.sh [version]     # e.g. install.sh 1.0.3 — defaults to the latest release
set -euo pipefail

REPO="ishm6m/DevDock"
APP_NAME="DevDock"
DEST="/Applications"
VERSION="${1:-}"

command -v curl >/dev/null || { echo "error: curl is required" >&2; exit 1; }

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "error: DevDock is macOS-only (this is $(uname -s))" >&2
  exit 1
fi

# macOS 14 (Sonoma) or later, per the app's deployment target.
major="$(sw_vers -productVersion | cut -d. -f1)"
if (( major < 14 )); then
  echo "error: DevDock needs macOS 14 (Sonoma) or later; found $(sw_vers -productVersion)" >&2
  exit 1
fi

echo "==> Locating release"
if [[ -n "$VERSION" ]]; then
  API="https://api.github.com/repos/${REPO}/releases/tags/v${VERSION#v}"
else
  API="https://api.github.com/repos/${REPO}/releases/latest"
fi

# Parse without jq (not installed on a stock Mac): pull the first .dmg asset URL.
DMG_URL="$(curl -fsSL "$API" \
  | grep -o '"browser_download_url"[[:space:]]*:[[:space:]]*"[^"]*\.dmg"' \
  | head -1 | sed -E 's/.*"(https[^"]*)"$/\1/')"

if [[ -z "$DMG_URL" ]]; then
  echo "error: no .dmg asset found at $API" >&2
  echo "       Check https://github.com/${REPO}/releases for available builds." >&2
  exit 1
fi

TMP="$(mktemp -d)"
MOUNT=""
cleanup() {
  [[ -n "$MOUNT" ]] && hdiutil detach "$MOUNT" -quiet 2>/dev/null || true
  rm -rf "$TMP"
}
trap cleanup EXIT

DMG="$TMP/${APP_NAME}.dmg"
echo "==> Downloading $(basename "$DMG_URL")"
curl -fL --progress-bar "$DMG_URL" -o "$DMG"

echo "==> Mounting disk image"
MOUNT="$TMP/mnt"
mkdir -p "$MOUNT"
hdiutil attach "$DMG" -mountpoint "$MOUNT" -nobrowse -quiet

SRC="$MOUNT/${APP_NAME}.app"
[[ -d "$SRC" ]] || { echo "error: ${APP_NAME}.app not found inside the disk image" >&2; exit 1; }

# Replacing a running bundle leaves the old process on deleted files; quit first.
if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
  echo "==> Quitting the running ${APP_NAME}"
  osascript -e "quit app \"${APP_NAME}\"" 2>/dev/null || true
  sleep 2
fi

echo "==> Installing to ${DEST}/${APP_NAME}.app"
rm -rf "${DEST:?}/${APP_NAME}.app"
cp -R "$SRC" "$DEST/"

# curl-downloaded files carry no quarantine flag; strip it anyway so the install
# is warning-free even if this script was fed a browser-downloaded image.
xattr -dr com.apple.quarantine "${DEST}/${APP_NAME}.app" 2>/dev/null || true

echo "==> Launching"
open -a "${DEST}/${APP_NAME}.app"
echo "Done — look for the rocket icon in your menu bar."
