#!/bin/bash
# Build "Biblia Clásica" (AppKit, macOS 10.13+): universal x86_64 (10.13) + arm64 (11.0), embedded Swift runtime,
# ad-hoc signature. Only needs the Command Line Tools.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(tr -d ' \n' < "$ROOT/VERSION")"
APP="$ROOT/build/Biblia Clásica.app"
EXE="BibliaClassic"
SWIFT5_LIBS="${SWIFT5_LIBS:-/Library/Developer/CommandLineTools/usr/lib/swift-5.0/macosx}"
X86_DIR="$ROOT/build/classic-x86_64"
ARM_DIR="$ROOT/build/classic-arm64"

cd "$ROOT/App"
swift build -c release --product "$EXE" --triple x86_64-apple-macosx10.13 --scratch-path "$X86_DIR"
swift build -c release --product "$EXE" --triple arm64-apple-macosx11.0   --scratch-path "$ARM_DIR"
X86_BIN="$(swift build -c release --product "$EXE" --triple x86_64-apple-macosx10.13 --scratch-path "$X86_DIR" --show-bin-path)"
ARM_BIN="$(swift build -c release --product "$EXE" --triple arm64-apple-macosx11.0   --scratch-path "$ARM_DIR" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
EXEPATH="$APP/Contents/MacOS/Biblia Clasica"
# The embedded runtime (swift-5.0/macosx) is x86_64 only: add the Frameworks rpath to the x86_64 slice ONLY;
# the arm64 slice (macOS 11+) uses the OS runtime in /usr/lib/swift.
X86_THIN="$ROOT/build/classic-x86_64-thin"
cp "$X86_BIN/$EXE" "$X86_THIN"
if ! otool -l "$X86_THIN" | grep -q "@executable_path/../Frameworks"; then
  install_name_tool -add_rpath "@executable_path/../Frameworks" "$X86_THIN"
fi
lipo -create "$X86_THIN" "$ARM_BIN/$EXE" -output "$EXEPATH"
rm -f "$X86_THIN"

cp "$ROOT/App/Icon/Biblia.icns" "$APP/Contents/Resources/Biblia.icns"

# Resource bundle (bible.sqlite): copy dereferencing the symlink so the real file ends up inside the .app.
BUNDLE="BibliaApp_BibliaCore.bundle"
cp -RL "$X86_BIN/$BUNDLE" "$APP/Contents/Resources/$BUNDLE"
[ -d "$X86_BIN/GRDB_GRDB.bundle" ] && cp -RL "$X86_BIN/GRDB_GRDB.bundle" "$APP/Contents/Resources/" || true
test -s "$APP/Contents/Resources/$BUNDLE/Resources/bible.sqlite"
[ ! -L "$APP/Contents/Resources/$BUNDLE/Resources/bible.sqlite" ]

# Embed the Swift runtime (macOS < 10.14.4 has none): only the libswift*.dylib the x86_64 slice references,
# plus their own transitive @rpath dependencies.
need=()
collect() {  # $1 = mach-o file (thin or universal: use the x86_64 slice)
  otool -arch x86_64 -L "$1" | awk '/@rpath\/libswift/ {print $1}' | sed 's#@rpath/##'
}
queue=($(collect "$EXEPATH"))
while [ ${#queue[@]} -gt 0 ]; do
  lib="${queue[0]}"; queue=("${queue[@]:1}")
  case " ${need[*]-} " in *" $lib "*) continue ;; esac
  src="$SWIFT5_LIBS/$lib"
  [ -f "$src" ] || { echo "missing $src" >&2; exit 1; }
  need+=("$lib")
  cp "$src" "$APP/Contents/Frameworks/$lib"
  queue+=($(collect "$src"))
done
echo "Embedded Swift libs: ${need[*]}"


cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>org.biblia.clasica</string>
  <key>CFBundleName</key><string>Biblia Clásica</string>
  <key>CFBundleDisplayName</key><string>Biblia Clásica</string>
  <key>CFBundleExecutable</key><string>Biblia Clasica</string>
  <key>CFBundleIconFile</key><string>Biblia</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.reference</string>
  <key>NSHumanReadableCopyright</key><string>Texto bíblico de dominio público. Ver Acerca de.</string>
  <key>LSMinimumSystemVersion</key><string>10.13</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

# Sign inner dylibs first, then the bundle (ad-hoc).
for f in "$APP/Contents/Frameworks/"*.dylib; do codesign --force -s - "$f"; done
codesign --force --deep -s - "$APP"
codesign -dv "$APP" 2>&1 | head -5 || true
echo "OK: $APP"
