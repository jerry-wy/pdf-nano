#!/bin/bash
set -euo pipefail
cd -P "$(dirname "$0")/.."
mkdir -p build
STAGING=$(mktemp -d "$PWD/build/.package.XXXXXX")
trap 'rm -rf "$STAGING"' EXIT
APP="$STAGING/PDF Nano.app"
CACHE="$PWD/build/swift-cache-native"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$CACHE"
cp macos/Info.plist "$APP/Contents/Info.plist"
cp macos/Welcome.pdf "$APP/Contents/Resources/Welcome.pdf"
cp -R macos/AgentRenderer "$APP/Contents/Resources/AgentRenderer"
ARCH="$(uname -m)"
xcrun swiftc -swift-version 5 -O -module-name PDFNano -module-cache-path "$CACHE" -target "$ARCH-apple-macosx13.0" macos/main.swift macos/App.swift macos/Icons.swift macos/Document.swift macos/OCRTextLayer.swift macos/OCRRecognition.swift macos/OCRProgressView.swift macos/Reader.swift macos/PageSidebar.swift macos/OutlineLayout.swift macos/OutlineTracking.swift macos/ReaderPanels.swift macos/ModelPicker.swift macos/MarginNotes.swift macos/AgentBridge.swift macos/CodexAccount.swift macos/AgentAccountView.swift macos/ReadingAgent.swift macos/AgentPanel.swift macos/AgentChatViews.swift macos/AgentMathTranscript.swift macos/AgentRendererAssets.swift macos/ChatHistory.swift macos/ChatHistoryView.swift macos/SmokeTests.swift -o "$APP/Contents/MacOS/PDFNano" -framework AppKit -framework PDFKit -framework Vision -framework WebKit
xcrun swiftc -module-cache-path "$CACHE" macos/MakeIcon.swift -o build/make-icon
build/make-icon "$PWD/build/AppIcon.iconset"
cp build/AppIcon.iconset/icon_32x32@2x.png "$APP/Contents/Resources/TitleIcon.png"
cp build/AppIcon.iconset/icon_512x512@2x.png "$APP/Contents/Resources/ApplicationIcon.png"
ICON_NAME=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' macos/Info.plist)
python3 scripts/make-icns.py build/AppIcon.iconset "$APP/Contents/Resources/$ICON_NAME.icns"
if [ "$ICON_NAME" != "AppIcon" ]; then
    rm -f "$APP/Contents/Resources/AppIcon.icns"
fi
for old_icon in "$APP"/Contents/Resources/PDFNanoIcon-v*.icns; do
    if [ "$old_icon" != "$APP/Contents/Resources/$ICON_NAME.icns" ]; then
        rm -f "$old_icon"
    fi
done
# Finder may add presentation metadata while the build folder is open.
# It is not part of the app and prevents signing an existing bundle.
for attribute in com.apple.FinderInfo com.apple.ResourceFork; do
    # xattr also returns nonzero when this optional attribute is absent.
    xattr -dr "$attribute" "$APP" 2>/dev/null || true
done
# A valid signature does not imply the executable permission survived copying.
chmod 755 "$APP/Contents/MacOS/PDFNano"
codesign --force --sign - "$APP"
test -x "$APP/Contents/MacOS/PDFNano"
codesign --verify --deep --strict "$APP"
ditto -c -k --keepParent --norsrc "$APP" "$STAGING/PDF Nano.zip"
mv -f "$STAGING/PDF Nano.zip" "$PWD/build/PDF Nano.zip"
printf '\nBuilt %s\nRun Install PDF Nano.command to install or update the app.\n' "$PWD/build/PDF Nano.zip"
