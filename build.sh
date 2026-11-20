#!/bin/sh
# Builds AppFreezer.app next to this script. No Xcode project needed.
set -eu
cd "$(dirname "$0")"

APP=AppFreezer.app
VERSION=${VERSION:-1.1.0}

# App icon: generated once; delete AppIcon.icns to regenerate.
if [ ! -f AppIcon.icns ]; then
  TMP=$(mktemp -d)
  swift make-icon.swift "$TMP/icon.png"
  mkdir "$TMP/AppIcon.iconset"
  for s in 16 32 128 256 512; do
    sips -z $s $s "$TMP/icon.png" --out "$TMP/AppIcon.iconset/icon_${s}x${s}.png" >/dev/null
    sips -z $((s * 2)) $((s * 2)) "$TMP/icon.png" --out "$TMP/AppIcon.iconset/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$TMP/AppIcon.iconset" -o AppIcon.icns
  rm -rf "$TMP"
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp AppIcon.icns "$APP/Contents/Resources/"

# Universal binary: Apple silicon + Intel.
BIN=$(mktemp -d)
for arch in arm64 x86_64; do
  swiftc -O -parse-as-library -target "$arch-apple-macos14.0" AppFreezer.swift -o "$BIN/AppFreezer-$arch"
done
lipo -create "$BIN/AppFreezer-arm64" "$BIN/AppFreezer-x86_64" -output "$APP/Contents/MacOS/AppFreezer"
rm -rf "$BIN"

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>AppFreezer</string>
  <key>CFBundleExecutable</key><string>AppFreezer</string>
  <key>CFBundleIdentifier</key><string>io.github.yurishevtsov.appfreezer</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
EOF

codesign --force --sign - "$APP"
echo "Built $(pwd)/$APP ($VERSION)"
