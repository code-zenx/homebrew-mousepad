#!/bin/bash
# Builds dist/Mousepad.app from the SwiftPM package. No Xcode needed.
set -euo pipefail
cd "$(dirname "$0")/.."

if [ ! -f Resources/AppIcon.icns ]; then
    echo "generating icon"
    swift Scripts/make-icon.swift Resources/AppIcon.iconset
    iconutil -c icns Resources/AppIcon.iconset -o Resources/AppIcon.icns
    rm -rf Resources/AppIcon.iconset
fi

swift build -c release 2>&1 | grep -v '^\[' | tail -5

APP=dist/Mousepad.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Mousepad "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
printf 'APPL????' > "$APP/Contents/PkgInfo"
codesign --force --deep --sign - "$APP" 2>&1 | grep -v 'replacing existing signature' || true
echo "built $APP"
