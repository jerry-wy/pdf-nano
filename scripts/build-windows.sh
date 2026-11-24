#!/bin/bash
set -euo pipefail
cd -P "$(dirname "$0")/.."
npm run build
mkdir -p build/release
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
cp windows/main.go "$stage/"
cp -R dist "$stage/"
version=$(node -p "require('./package.json').version")
archive="$PWD/build/release/PDF-Nano-Windows-x64-$version.zip"
cd "$stage"
CGO_ENABLED=0 GOOS=windows GOARCH=amd64 go build -trimpath -ldflags="-s -w" -o "PDF Nano.exe" main.go
zip -q "$stage/release.zip" "PDF Nano.exe"
mv "$stage/release.zip" "$archive"
