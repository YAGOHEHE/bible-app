#!/bin/bash
# Compila en release y ensambla build/Biblia.app (firma ad-hoc). Solo requiere Command Line Tools.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(tr -d ' \n' < "$ROOT/VERSION")"
APP="$ROOT/build/Biblia.app"

cd "$ROOT/App"
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/BibliaApp" "$APP/Contents/MacOS/Biblia"
cp "$ROOT/App/Icon/Biblia.icns" "$APP/Contents/Resources/Biblia.icns"
# Paquete de recursos de SwiftPM (contiene Resources/bible.sqlite). BibleDatabase lo busca en Contents/Resources.
cp -R "$BIN_DIR/BibliaApp_BibliaApp.bundle" "$APP/Contents/Resources/"
# GRDB aporta su propio bundle (PrivacyInfo); se copia si existe.
[ -d "$BIN_DIR/GRDB_GRDB.bundle" ] && cp -R "$BIN_DIR/GRDB_GRDB.bundle" "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>org.biblia.lector</string>
  <key>CFBundleName</key><string>Biblia</string>
  <key>CFBundleDisplayName</key><string>Biblia</string>
  <key>CFBundleExecutable</key><string>Biblia</string>
  <key>CFBundleIconFile</key><string>Biblia</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.reference</string>
  <key>NSHumanReadableCopyright</key><string>Texto bíblico de dominio público. Ver Acerca de.</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

codesign --force --deep -s - "$APP"
codesign -dv "$APP" 2>&1 | head -5 || true
spctl -a -vv "$APP" 2>&1 || true   # esperado: rechazado (firma ad-hoc, sin notarizar)
echo "OK: $APP"
