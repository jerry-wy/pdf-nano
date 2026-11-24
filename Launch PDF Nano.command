#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
if [ ! -x '/Applications/PDF Nano.app/Contents/MacOS/PDFNano' ]; then
    exec bash 'Install PDF Nano.command'
fi
open '/Applications/PDF Nano.app'
