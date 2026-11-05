#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build/objects build/RAMLOOP.app/Contents/MacOS build/RAMLOOP.app/Contents/Resources
for arch in arm64 x86_64; do
    xcrun swiftc -O -target "${arch}-apple-macos13.0" Sources/main.swift -o "build/objects/$arch"
done
lipo -create build/objects/arm64 build/objects/x86_64 -output build/RAMLOOP.app/Contents/MacOS/RAMLOOP
cp Resources/Info.plist build/RAMLOOP.app/Contents/
cp Resources/RAMLOOP.icns build/RAMLOOP.app/Contents/Resources/
codesign --force --sign - build/RAMLOOP.app
codesign --verify --strict build/RAMLOOP.app
ditto -c -k --keepParent build/RAMLOOP.app build/RAMLOOP.zip
printf 'Built build/RAMLOOP.app and build/RAMLOOP.zip\n'
