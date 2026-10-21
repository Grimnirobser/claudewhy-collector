#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD="$ROOT/build"
OUT="$ROOT/dist"
APP="$BUILD/溯因采集器.app"
VERSION="0.2.0"
NAME="Suyin-Collector-$VERSION-universal"

if [[ "$(uname -s)" != "Darwin" ]]; then
  printf 'This collector requires macOS and the Xcode Command Line Tools.\n' >&2
  exit 1
fi
for tool in swiftc lipo codesign pkgbuild hdiutil python3; do
  command -v "$tool" >/dev/null || { printf 'Missing build tool: %s\n' "$tool" >&2; exit 1; }
done

mkdir -p "$APP/Contents/MacOS" "$OUT"
swiftc -swift-version 5 -O -target arm64-apple-macos13.0 "$ROOT/main.swift" -o "$BUILD/collector-arm64"
swiftc -swift-version 5 -O -target x86_64-apple-macos13.0 "$ROOT/main.swift" -o "$BUILD/collector-x86_64"
lipo -create "$BUILD/collector-arm64" "$BUILD/collector-x86_64" -output "$APP/Contents/MacOS/collector"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>collector</string>
<key>CFBundleIdentifier</key><string>com.shinerain.banevidence</string>
<key>CFBundleName</key><string>溯因采集器</string>
<key>CFBundleDisplayName</key><string>溯因采集器</string>
<key>CFBundleVersion</key><string>0.2.0</string>
<key>CFBundleShortVersionString</key><string>0.2.0</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
codesign --verify --deep --strict "$APP"
pkgbuild --component "$APP" --install-location /Applications --identifier com.shinerain.banevidence --version "$VERSION" "$OUT/$NAME.pkg"
hdiutil create -volname "溯因采集器" -srcfolder "$APP" -ov -format UDZO "$OUT/$NAME.dmg"
python3 "$ROOT/download-info.py"
printf '\nBuild complete. App: %s\nPackages and checksums: %s\n' "$APP" "$OUT"
