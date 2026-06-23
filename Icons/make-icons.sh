#!/usr/bin/env bash
#
# Generates HighRise app icons for macOS, iOS/iPadOS, and Windows from master
# artwork. Run on a Mac (uses built-in `sips`); ImageMagick is needed only for
# the Windows .ico and for anchored (non-center) square cropping.
#
# Accepts PNG or JPEG. If a source isn't square it is auto-cropped to a square
# first (app icons must be square), so the landscape skyline art works directly.
#
# Usage:
#   ./Icons/make-icons.sh \
#       --macos "/path/HighRise App iCon 1280x768.jpg" \
#       --ios   "/path/HighRise App iCon 1280x768.jpg" \
#       [--crop center|left|right|top|bottom]   # default: center
#
# Shortcuts:
#   * Omit --ios / --win and they fall back to the --macos master.
#   * --crop chooses which part of a non-square source to keep (e.g. `left`
#     keeps the left of a wide banner). Anchors other than `center` need
#     ImageMagick; `center` works with sips alone.
#
# Framing notes (so the icons look right, not just exist):
#   * iOS/iPadOS & Windows – want a FULL-BLEED opaque square. The skyline JPEG
#     cropped square is exactly right; the OS rounds the corners itself.
#   * macOS – classic macOS icons are a rounded "squircle" with transparent
#     margins, which needs a PNG-with-alpha master. From an opaque JPEG you get
#     a full square tile (still valid, just not the padded-squircle look).
#
# Nothing is uploaded; output lands under Icons/.
set -euo pipefail

cd "$(dirname "$0")"               # -> Icons/
ROOT="$(pwd)"

MAC_SRC="" IOS_SRC="" WIN_SRC="" CROP="center"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --macos) MAC_SRC="$2"; shift 2 ;;
    --ios)   IOS_SRC="$2"; shift 2 ;;
    --win)   WIN_SRC="$2"; shift 2 ;;
    --crop)  CROP="$2";    shift 2 ;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

MAC_SRC="${MAC_SRC:-$ROOT/masters/HighRise-macos-1024.png}"
IOS_SRC="${IOS_SRC:-$MAC_SRC}"
WIN_SRC="${WIN_SRC:-$MAC_SRC}"
for f in "$MAC_SRC" "$IOS_SRC" "$WIN_SRC"; do
  [[ -f "$f" ]] || { echo "Master artwork not found: $f" >&2; exit 1; }
done

has() { command -v "$1" >/dev/null 2>&1; }
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT

dims() { # file -> "W H"
  if has sips; then
    sips -g pixelWidth -g pixelHeight "$1" \
      | awk '/pixelWidth/{w=$2}/pixelHeight/{h=$2}END{print w, h}'
  elif has magick; then magick identify -format '%w %h' "$1"
  elif has identify; then identify -format '%w %h' "$1"
  else echo "0 0"; fi
}

# Crop a source down to a centered/anchored square PNG.
prepare_square() { # src dst anchor
  local src="$1" dst="$2" anchor="$3" w h side
  read -r w h < <(dims "$src")
  side=$(( w < h ? w : h ))
  if [[ "$w" -eq "$h" ]]; then
    if has sips; then sips -s format png "$src" --out "$dst" >/dev/null; else cp "$src" "$dst"; fi
    echo "$side"; return
  fi
  if [[ "$anchor" == "center" ]] && has sips; then
    # sips -c takes height then width; centered.
    sips -s format png -c "$side" "$side" "$src" --out "$dst" >/dev/null
    echo "$side"; return
  fi
  local grav
  case "$anchor" in
    left) grav=West ;; right) grav=East ;; top) grav=North ;; bottom) grav=South ;;
    *) grav=Center ;;
  esac
  if has magick;   then magick  "$src" -gravity "$grav" -crop "${side}x${side}+0+0" +repage "$dst"
  elif has convert; then convert "$src" -gravity "$grav" -crop "${side}x${side}+0+0" +repage "$dst"
  else
    echo "  anchor '$anchor' needs ImageMagick; using centered sips crop instead." >&2
    sips -s format png -c "$side" "$side" "$src" --out "$dst" >/dev/null
  fi
  echo "$side"
}

resize() { # src dst px
  local src="$1" dst="$2" px="$3"
  if has sips; then sips -s format png -z "$px" "$px" "$src" --out "$dst" >/dev/null
  elif has magick; then magick "$src" -resize "${px}x${px}" "$dst"
  elif has convert; then convert "$src" -resize "${px}x${px}" "$dst"
  else echo "Need sips or ImageMagick to resize." >&2; exit 1; fi
}

echo "Cropping square masters (anchor: $CROP)…"
MAC_SQ="$WORK/mac.png"; SIDE=$(prepare_square "$MAC_SRC" "$MAC_SQ" "$CROP")
IOS_SQ="$WORK/ios.png"; prepare_square "$IOS_SRC" "$IOS_SQ" "$CROP" >/dev/null
WIN_SQ="$WORK/win.png"; prepare_square "$WIN_SRC" "$WIN_SQ" "$CROP" >/dev/null
[[ "${SIDE:-0}" -gt 0 && "${SIDE}" -lt 1024 ]] && \
  echo "  note: square master is ${SIDE}px; sizes above ${SIDE} are upscaled. A ≥1024px source is sharper." >&2

echo "macOS  → AppIcon-macOS.appiconset"
MAC_SET="$ROOT/AppIcon-macOS.appiconset"
declare -a MAC=(
  "icon_16x16.png:16"       "icon_16x16@2x.png:32"
  "icon_32x32.png:32"       "icon_32x32@2x.png:64"
  "icon_128x128.png:128"    "icon_128x128@2x.png:256"
  "icon_256x256.png:256"    "icon_256x256@2x.png:512"
  "icon_512x512.png:512"    "icon_512x512@2x.png:1024"
)
for pair in "${MAC[@]}"; do resize "$MAC_SQ" "$MAC_SET/${pair%%:*}" "${pair##*:}"; done

echo "iOS    → AppIcon-iOS.appiconset"
resize "$IOS_SQ" "$ROOT/AppIcon-iOS.appiconset/AppIcon-iOS-1024.png" 1024

echo "win    → windows/HighRise.ico"
mkdir -p "$ROOT/windows"
if has magick || has convert; then
  files=()
  for px in 16 24 32 48 64 128 256; do resize "$WIN_SQ" "$WORK/$px.png" "$px"; files+=("$WORK/$px.png"); done
  if has magick; then magick "${files[@]}" "$ROOT/windows/HighRise.ico"
  else convert "${files[@]}" "$ROOT/windows/HighRise.ico"; fi
else
  echo "  (skipped: install ImageMagick — 'brew install imagemagick' — for .ico)" >&2
fi

cat <<DONE

Done. Generated:
  Icons/AppIcon-macOS.appiconset/   (10 PNGs + Contents.json)
  Icons/AppIcon-iOS.appiconset/     (1024 PNG + Contents.json)
  Icons/windows/HighRise.ico        (if ImageMagick was available)

If the crop clipped the skyline, re-run with --crop left|right|center.
Next: wire the macOS icon into the app — see Icons/README.md (§ "Wiring macOS").
DONE
