#!/bin/bash
# Compila en release y ensambla build/BibliaApp.app (firma ad-hoc). Solo requiere Command Line Tools.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/BibliaApp.app"

cd "$ROOT/App"
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/BibliaApp" "$APP/Contents/MacOS/BibliaApp"
# Paquete de recursos de SwiftPM (contiene Resources/bible.sqlite). BibleDatabase lo busca en Contents/Resources.
cp -R "$BIN_DIR/BibliaApp_BibliaApp.bundle" "$APP/Contents/Resources/"
# GRDB aporta su propio bundle (PrivacyInfo); se copia si existe.
[ -d "$BIN_DIR/GRDB_GRDB.bundle" ] && cp -R "$BIN_DIR/GRDB_GRDB.bundle" "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>org.bibliaapp.reader</string>
  <key>CFBundleName</key><string>BibliaApp</string>
  <key>CFBundleDisplayName</key><string>BibliaApp</string>
  <key>CFBundleExecutable</key><string>BibliaApp</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

codesign --force --deep -s - "$APP"
echo "OK: $APP"
