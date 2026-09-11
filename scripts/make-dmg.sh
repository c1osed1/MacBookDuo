#!/usr/bin/env bash
# Build a drag-to-Applications DMG from a .app bundle.
set -euo pipefail

usage() {
  echo "usage: $0 <App.app> <MacBookDuo-1.0.0.dmg>" >&2
  exit 1
}

APP="${1:-}"
OUT="${2:-}"
[[ -d "${APP}" && -n "${OUT}" ]] || usage

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BACKGROUND="${ROOT}/packaging/dmg-background.png"
VOLNAME="MacBook Duo"
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/macbookduo-dmg.XXXXXX")"
cleanup() { rm -rf "${STAGE}" "${OUT%.dmg}.rw.dmg"; }
trap cleanup EXIT

ditto "${APP}" "${STAGE}/MacBook Duo.app"
ln -s /Applications "${STAGE}/Applications"

if command -v create-dmg >/dev/null 2>&1; then
  args=(
    --volname "${VOLNAME}"
    --window-pos 200 120
    --window-size 800 500
    --icon-size 128
    --icon "MacBook Duo.app" 200 250
    --hide-extension "MacBook Duo.app"
    --app-drop-link 600 250
    --no-internet-enable
    --overwrite
  )
  if [[ -f "${BACKGROUND}" ]]; then
    args+=(--background "${BACKGROUND}")
  fi
  ICNS="${APP}/Contents/Resources/AppIcon.icns"
  if [[ ! -f "${ICNS}" ]]; then
    ICNS="${ROOT}/packaging/AppIcon.icns"
  fi
  if [[ -f "${ICNS}" ]]; then
    args+=(--volicon "${ICNS}")
  fi
  rm -f "${OUT}"
  create-dmg "${args[@]}" "${OUT}" "${STAGE}"
  exit 0
fi

# Fallback: valid drag-install DMG without Finder layout chrome.
TMP_RW="${OUT%.dmg}.rw.dmg"
rm -f "${OUT}" "${TMP_RW}"
hdiutil create \
  -volname "${VOLNAME}" \
  -srcfolder "${STAGE}" \
  -ov \
  -fs HFS+ \
  -format UDZO \
  -imagekey zlib-level=9 \
  "${OUT}"
