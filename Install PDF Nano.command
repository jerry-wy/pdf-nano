#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
ARCHIVE="$PWD/build/PDF Nano.zip"
DESTINATION="/Applications/PDF Nano.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
CHECK_ONLY=false
case "${1:-}" in
    --check) CHECK_ONLY=true ;;
    "") ;;
    *) printf 'Usage: Install PDF Nano.command [--check]\n'; exit 1 ;;
esac
if [ ! -f "$ARCHIVE" ]; then
    bash scripts/build-mac.sh
fi
if "$CHECK_ONLY"; then
    STAGING=$(mktemp -d "${TMPDIR:-/tmp}/pdfnano-check.XXXXXX")
else
    STAGING=$(mktemp -d "/Applications/.pdf-nano-install.XXXXXX")
fi
cleanup() {
    # Restore the previous app if moving the verified replacement failed.
    if [ -d "$STAGING/Previous.app" ] && [ ! -e "$DESTINATION" ]; then
        mv "$STAGING/Previous.app" "$DESTINATION"
    fi
    rm -rf "$STAGING"
}
trap cleanup EXIT
ditto -x -k "$ARCHIVE" "$STAGING"
SOURCE="$STAGING/PDF Nano.app"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$SOURCE/Contents/Info.plist")" = 'app.pdfnano.reader'
test -x "$SOURCE/Contents/MacOS/PDFNano"
codesign --verify --deep --strict "$SOURCE"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$SOURCE/Contents/Info.plist")
if "$CHECK_ONLY"; then
    printf 'PASS: PDF Nano %s archive, executable permissions and code signature.\n' "$VERSION"
    exit 0
fi
if [ -e "$DESTINATION" ]; then
    test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$DESTINATION/Contents/Info.plist")" = 'app.pdfnano.reader'
fi
if pgrep -x PDFNano >/dev/null; then
    printf 'Closing PDF Nano. Save changes if prompted.\n'
    osascript -e 'tell application id "app.pdfnano.reader" to quit'
    for attempt in {1..30}; do
        if ! pgrep -x PDFNano >/dev/null; then break; fi
        sleep 1
    done
    if pgrep -x PDFNano >/dev/null; then
        printf 'PDF Nano is still open. Finish saving and quit, then run this installer again.\n'
        exit 1
    fi
fi
if [ -e "$DESTINATION" ]; then
    mv "$DESTINATION" "$STAGING/Previous.app"
fi
mv "$SOURCE" "$DESTINATION"
python3 scripts/clean-mac-copies.py "$DESTINATION"
if ! "$LSREGISTER" -f "$DESTINATION"; then
    printf 'The app is installed, but macOS could not refresh its Open With entry.\n'
fi
open "$DESTINATION"
printf 'Installed PDF Nano %s in Applications.\n' "$VERSION"
