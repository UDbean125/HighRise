#!/bin/sh
#
# Archive and upload BOTH App Store builds in one shot:
#   1. HighRise-MAS   (sandboxed macOS build — the only macOS scheme that
#                      passes App Store validation; the plain HighRise scheme
#                      is the unsandboxed Developer ID build)
#   2. HighRiseMobile (iOS + iPadOS)
#
# Both share bundle ID com.bryansnotes.highrise, so both land on the same
# App Store Connect record as one Universal Purchase app.
#
# Usage (on a Mac, signed into Xcode with your Apple ID):
#
#   ./Tools/upload-appstore.sh TEAMID          # 10-char Team ID
#   DEVELOPMENT_TEAM=TEAMID ./Tools/upload-appstore.sh
#
# Find your Team ID: Xcode ▸ Settings ▸ Accounts ▸ (your Apple ID) ▸ team
# row, or developer.apple.com ▸ Membership. -allowProvisioningUpdates lets
# xcodebuild create/refresh the distribution certificate and profiles
# automatically using the account signed into Xcode.

set -e

TEAM="${1:-${DEVELOPMENT_TEAM:-}}"
if [ -z "$TEAM" ] || [ "$TEAM" = "TEAMID" ]; then
  echo "error: pass your REAL 10-character Apple Developer Team ID (not the word TEAMID)." >&2
  echo "  Find it: Xcode > Settings > Accounts > click your team - the ID is shown there," >&2
  echo "  or developer.apple.com > Membership. It looks like A1B2C3D4E5." >&2
  echo "  Then run:  ./Tools/upload-appstore.sh A1B2C3D4E5" >&2
  exit 1
fi
case "$TEAM" in
  *[!A-Z0-9]*|??????????*?|?|??|???|????|?????|??????|???????|????????|?????????)
    echo "error: '$TEAM' doesn't look like a Team ID (10 uppercase letters/digits, e.g. A1B2C3D4E5)." >&2
    exit 1;;
esac
if [ "$(uname)" != "Darwin" ]; then
  echo "error: this script needs a Mac with Xcode." >&2
  exit 1
fi

cd "$(dirname "$0")/.."

command -v xcodegen >/dev/null || { echo "error: brew install xcodegen first." >&2; exit 1; }
echo "==> Regenerating Xcode project"
xcodegen generate

BUILD_DIR="build/appstore"
mkdir -p "$BUILD_DIR"

EXPORT_PLIST="$BUILD_DIR/ExportOptions.plist"
cat > "$EXPORT_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>app-store-connect</string>
    <key>destination</key>
    <string>upload</string>
    <key>teamID</key>
    <string>$TEAM</string>
</dict>
</plist>
EOF

# Note: xcodebuild output goes to a log file and the exit code is checked
# directly — piping to tail would swallow failures under plain sh (no
# pipefail), which once made this script print "uploaded" after a failed
# archive.
archive_and_upload() {
    scheme="$1"; dest="$2"
    archive="$BUILD_DIR/$scheme.xcarchive"
    log="$BUILD_DIR/$scheme.log"
    echo ""
    echo "==> Archiving $scheme (log: $log)"
    if ! xcodebuild archive \
        -scheme "$scheme" \
        -destination "$dest" \
        -archivePath "$archive" \
        DEVELOPMENT_TEAM="$TEAM" \
        -allowProvisioningUpdates \
        > "$log" 2>&1; then
        echo "error: archiving $scheme FAILED. Last 25 log lines:" >&2
        tail -25 "$log" >&2
        exit 1
    fi
    echo "==> Uploading $scheme to App Store Connect"
    if ! xcodebuild -exportArchive \
        -archivePath "$archive" \
        -exportOptionsPlist "$EXPORT_PLIST" \
        -allowProvisioningUpdates \
        >> "$log" 2>&1; then
        echo "error: uploading $scheme FAILED. Last 25 log lines:" >&2
        tail -25 "$log" >&2
        exit 1
    fi
    echo "==> $scheme uploaded successfully."
}

archive_and_upload "HighRise-MAS"   "generic/platform=macOS"
archive_and_upload "HighRiseMobile" "generic/platform=iOS"

echo ""
echo "Done. Both builds are processing on App Store Connect (10-30 min)."
echo "Next: appstoreconnect.apple.com ▸ your app ▸ each platform tab ▸"
echo "select the new build on the version page and Submit for Review."
