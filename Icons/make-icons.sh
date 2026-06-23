#!/usr/bin/env bash
#
# Generates HighRise app icons for macOS, iOS/iPadOS, and Windows from master
# PNG artwork. Run this on a Mac (uses `sips`, built in); Windows .ico output
# additionally needs ImageMagick (`brew install imagemagick`).
#
# Usage:
#   ./Icons/make-icons.sh \
#       --macos "/Volumes/Satechi/HenSolutions/Apps/HighRise/HighRise iCons/<square-icon>.png" \
#       --ios   "/Volumes/Satechi/HenSolutions/Apps/HighRise/HighRise iCons/<full-bleed-square>.png" \
#       --win   "/Volumes/Satechi/HenSolutions/Apps/HighRise/HighRise iCons/<square-icon>.png"
#
# Shortcuts:
#   * Omit --ios / --win and they fall back to the --macos master.
#   * Omit all flags and it looks for Icons/masters/HighRise-{macos,ios,win}-1024.png
#
# Framing notes (so the icons actually look right, not just exist):
#   * macOS  – use the rounded-square "glass" artwork WITH its transparent
#              margins. macOS draws the icon as-is; the squircle/glass look
#              should already be baked into the PNG.
#   * iOS/iPadOS – use a FULL-BLEED, opaque square (no rounded corners, no
#              transparency). The OS masks the corners itself; a pre-rounded
#              icon gets double-rounded and looks wrong.
#   * Windows – full-bleed square works best, same as iOS.
#
# Masters should be 1024x1024 (or larger square). Nothing is uploaded; output
# lands under Icons/.
set -euo pipefail

cd "$(dirname "$0")"               # -> Icons/
ROOT="$(pwd)"

MAC_SRC="" IOS_SRC="" WIN_SRC=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --macos) MAC_SRC="$2"; shift 2 ;;
    --ios)   IOS_SRC="$2"; shift 2 ;;
    --win)   WIN_SRC="$2"; shift 2 ;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

# Defaults / fallbacks.
MAC_SRC="${MAC_SRC:-$ROOT/masters/HighRise-macos-1024.png}"
IOS_SRC="${IOS_SRC:-$MAC_SRC}"
WIN_SRC="${WIN_SRC:-$MAC_SRC}"

for f in "$MAC_SRC" "$IOS_SRC" "$WIN_SRC"; do
  [[ -f "$f" ]] || { echo "Master artwork not found: $f" >&2; exit 1; }
done

# --- resize helper: prefer sips (macOS built-in), fall back to ImageMagick ---
resize() { # src dst px
  local src="$1" dst="$2" px="$3"
  if command -v sips >/dev/null 2>&1; then
    sips -s format png -z "$px" "$px" "$src" --out "$dst" >/dev/null
  elif command -v magick >/dev/null 2>&1; then
    magick "$src" -resize "${px}x${px}" "$dst"
  elif command -v convert >/dev/null 2>&1; then
    convert "$src" -resize "${px}x${px}" "$dst"
  else
    echo "Need sips (macOS) or ImageMagick to resize." >&2; exit 1
  fi
}

# --- macOS: 16/32/128/256/512 at @1x and @2x into the .appiconset ----------
echo "macOS  → AppIcon-macOS.appiconset"
MAC_SET="$ROOT/AppIcon-macOS.appiconset"
declare -a MAC=(
  "icon_16x16.png:16"       "icon_16x16@2x.png:32"
  "icon_32x32.png:32"       "icon_32x32@2x.png:64"
  "icon_128x128.png:128"    "icon_128x128@2x.png:256"
  "icon_256x256.png:256"    "icon_256x256@2x.png:512"
  "icon_512x512.png:512"    "icon_512x512@2x.png:1024"
)
for pair in "${MAC[@]}"; do
  resize "$MAC_SRC" "$MAC_SET/${pair%%:*}" "${pair##*:}"
done

# --- iOS / iPadOS: single 1024 universal marketing icon --------------------
echo "iOS    → AppIcon-iOS.appiconset"
resize "$IOS_SRC" "$ROOT/AppIcon-iOS.appiconset/AppIcon-iOS-1024.png" 1024

# --- Windows: multi-resolution .ico ----------------------------------------
echo "win    → windows/HighRise.ico"
mkdir -p "$ROOT/windows"
if command -v magick >/dev/null 2>&1 || command -v convert >/dev/null 2>&1; then
  TMP="$(mktemp -d)"; files=()
  for px in 16 24 32 48 64 128 256; do
    resize "$WIN_SRC" "$TMP/$px.png" "$px"; files+=("$TMP/$px.png")
  done
  if command -v magick >/dev/null 2>&1; then magick "${files[@]}" "$ROOT/windows/HighRise.ico"
  else convert "${files[@]}" "$ROOT/windows/HighRise.ico"; fi
  rm -rf "$TMP"
else
  echo "  (skipped: install ImageMagick — 'brew install imagemagick' — for .ico)" >&2
fi

cat <<DONE

Done. Generated:
  Icons/AppIcon-macOS.appiconset/   (10 PNGs + Contents.json)
  Icons/AppIcon-iOS.appiconset/     (1024 PNG + Contents.json)
  Icons/windows/HighRise.ico        (if ImageMagick was available)

Next: wire the macOS icon into the app — see Icons/README.md (§ "Wiring macOS").
DONE
