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

# Parse without jq (not installed on a stock Mac). Prefer a .dmg, fall back to a
# .zip so the installer keeps working if the release format ever changes.
ASSETS="$(curl -fsSL "$API" \
  | grep -o '"browser_download_url"[[:space:]]*:[[:space:]]*"[^"]*"' \
  | sed -E 's/.*"(https[^"]*)"$/\1/')"

ASSET_URL="$(grep -i '\.dmg$' <<<"$ASSETS" | head -1)"
[[ -z "$ASSET_URL" ]] && ASSET_URL="$(grep -i '\.zip$' <<<"$ASSETS" | head -1)"

if [[ -z "$ASSET_URL" ]]; then
  echo "error: no .dmg or .zip asset found at $API" >&2
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

ARCHIVE="$TMP/$(basename "$ASSET_URL")"
echo "==> Downloading $(basename "$ASSET_URL")"
curl -fL --progress-bar "$ASSET_URL" -o "$ARCHIVE"

if [[ "$ARCHIVE" == *.dmg ]]; then
  echo "==> Mounting disk image"
  MOUNT="$TMP/mnt"
  mkdir -p "$MOUNT"
  hdiutil attach "$ARCHIVE" -mountpoint "$MOUNT" -nobrowse -quiet
  SRC="$MOUNT/${APP_NAME}.app"
else
  echo "==> Extracting archive"
  # ditto preserves bundle metadata and symlinks correctly; unzip does not.
  ditto -x -k "$ARCHIVE" "$TMP/unpacked"
  SRC="$(find "$TMP/unpacked" -maxdepth 2 -name "${APP_NAME}.app" -print -quit)"
fi

[[ -n "$SRC" && -d "$SRC" ]] || { echo "error: ${APP_NAME}.app not found in the download" >&2; exit 1; }

# Replacing a running bundle leaves the old process on deleted files; quit first.
if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
  echo "==> Quitting the running ${APP_NAME}"
  osascript -e "quit app \"${APP_NAME}\"" 2>/dev/null || true
  sleep 2
fi

echo "==> Installing to ${DEST}/${APP_NAME}.app"
rm -rf "${DEST:?}/${APP_NAME}.app"
cp -R "$SRC" "$DEST/"

# Safety net. curl-downloaded files carry no com.apple.quarantine flag, so this
# is normally a no-op — it matters only if the archive reached this script by
# some other route. Verified not to disturb the ad-hoc code signature.
xattr -cr "${DEST}/${APP_NAME}.app" 2>/dev/null || true

echo "==> Launching"
open -a "${DEST}/${APP_NAME}.app"

cat <<EOF

  ✅ ${APP_NAME} installed to ${DEST}/${APP_NAME}.app — and launched.

  Look for the 🚀 rocket icon in your menu bar; it shows a live count of your
  running dev servers. Click it to see them, or open Preferences from the panel.

  No Gatekeeper warning appeared because this installer downloads with curl,
  which never applies the quarantine flag that triggers it.

EOF
