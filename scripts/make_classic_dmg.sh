#!/bin/bash
# Empaqueta build/Biblia Clásica.app (universal, 10.13+) en build/Biblia-Clasica-<versión>.dmg (UDZO).
# Reconstruye la app siempre, para que el DMG lleve la versión actual.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(tr -d ' \n' < "$ROOT/VERSION")"
"$ROOT/scripts/make_classic_app.sh"
APP="$ROOT/build/Biblia Clásica.app"
codesign --verify --deep --strict "$APP"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/Biblia Clásica.app"
ln -s /Applications "$STAGE/Applications"
cat > "$STAGE/LÉEME.txt" <<TXT
BIBLIA CLÁSICA $VERSION  -  Primera apertura / 首次打开

ES
Requiere macOS 10.13 (High Sierra) o posterior, en Mac Intel o Apple Silicon.
(Si tienes macOS 14 o posterior, puedes usar también la app "Biblia".)
1. Arrastra "Biblia Clásica.app" a la carpeta Aplicaciones (Applications).
2. La primera vez, macOS dirá que no puede verificar al desarrollador (la app no está notarizada):
   haz clic derecho (o Control + clic) sobre Biblia Clásica -> Abrir -> Abrir.
   Si no aparece el botón: Preferencias del Sistema -> Seguridad y privacidad -> General ->
   "Abrir de todos modos" (macOS 10.13 a 10.15) o "Abrir igualmente" (macOS 11 y posterior).
3. Solo es necesario la primera vez.
Tus datos (historial, notas, resaltados, marcadores) están en:
   ~/Library/Application Support/Biblia Clásica/
Los ajustes están en ~/Library/Preferences/org.biblia.clasica.plist
Textos bíblicos de dominio público.

中文
需要 macOS 10.13 (High Sierra) 或更高版本，支持 Intel 与 Apple Silicon 芯片的 Mac。
（如果系统是 macOS 14 或更高，也可以使用 "Biblia" 应用。）
1. 把 "Biblia Clásica.app" 拖到「应用程序」(Applications) 文件夹。
2. 第一次打开时，macOS 会提示无法验证开发者（应用未经公证）：请右键（或按住 Control 点击）
   Biblia Clásica -> 打开 -> 打开。
   如果没有"打开"按钮：系统偏好设置 -> 安全性与隐私 -> 通用 ->
   点「仍然打开」（macOS 10.13–10.15 显示 "Abrir de todos modos"；macOS 11 及以后显示 "Abrir igualmente"）。
3. 只需第一次这样操作。
数据位置（历史、笔记、高亮、书签）：
   ~/Library/Application Support/Biblia Clásica/
圣经经文均为公有领域。
TXT
OUT="$ROOT/build/Biblia-Clasica-$VERSION.dmg"
rm -f "$OUT"
hdiutil create -volname "Biblia Clásica" -srcfolder "$STAGE" -ov -format UDZO "$OUT"
ls -lh "$OUT"
