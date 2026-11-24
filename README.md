# PDF Nano

```sh
bash scripts/build-mac.sh
bash "Install PDF Nano.command"
```

Requires macOS 13+ and Xcode Command Line Tools. Agent requires Codex and your own account.

## Download and run

Download the ZIP for your platform from the GitHub release assets and extract it.

- **macOS 13 or later** — Drag PDF Nano.app to Applications. The universal build runs on Apple Silicon and Intel. The distributed app uses an ad hoc signature, so macOS may ask you to allow it in Privacy & Security.
- **Windows x64** — Double-click PDF Nano.exe. It opens the browser edition in your default browser. Keep the console window open while reading and close it to quit. Notes are stored in that browser profile. This edition supports reading, searching, annotations and PDF export. The Codex reading assistant is available in the macOS edition.

To build the universal Mac archive, run `bash scripts/build-mac.sh --universal`. To build the Windows archive from macOS, install Go and the project's npm dependencies, then run `bash scripts/build-windows.sh`.
