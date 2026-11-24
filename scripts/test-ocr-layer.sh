#!/bin/bash
set -euo pipefail
cd -P "$(dirname "$0")/.."
STAGING=$(mktemp -d "${TMPDIR:-/tmp}/pdfnano-ocr-tests.XXXXXX")
trap 'rm -rf "$STAGING"' EXIT
xcrun swiftc -swift-version 5 -O -module-cache-path "$PWD/build/swift-cache-native" -target "$(uname -m)-apple-macosx13.0" macos/OCRTextLayer.swift macos/OCRRecognition.swift tests/native/OCRSelectionTests.swift -o "$STAGING/check-selection" -framework PDFKit -framework Vision
"$STAGING/check-selection"
xcrun swiftc -swift-version 5 -module-cache-path "$PWD/build/swift-cache-native" -target "$(uname -m)-apple-macosx13.0" macos/OCRTextLayer.swift macos/OCRLayerTests.swift -o "$STAGING/check-ocr"
"$STAGING/check-ocr" "$STAGING"
node scripts/verify-ocr-layer.mjs "$STAGING"
