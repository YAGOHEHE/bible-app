#!/bin/bash
# Empaqueta build/Biblia.app en build/Biblia-<versión>.dmg (UDZO) con enlace a /Applications y LÉEME.txt.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(tr -d ' \n' < "$ROOT/VERSION")"
APP="$ROOT/build/Biblia.app"
[ -d "$APP" ] || "$ROOT/scripts/make_app.sh"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/Biblia.app"
ln -s /Applications "$STAGE/Applications"
cat > "$STAGE/LÉEME.txt" <<TXT
BIBLIA $VERSION  -  Primera apertura / 首次打开

ES
1. Arrastra Biblia.app a la carpeta Aplicaciones (Applications).
2. La primera vez, macOS dirá que no puede verificar la app (no está en la App Store):
   haz clic derecho (o Control + clic) sobre Biblia -> Abrir -> Abrir.
   Si no aparece el botón: Ajustes del Sistema -> Privacidad y seguridad -> baja hasta
   "Biblia" -> "Abrir igualmente".
3. Solo es necesario la primera vez. Requiere macOS 14 (Sonoma) o superior.
Textos bíblicos de dominio público (ver "Acerca de Biblia" dentro de la app).

中文
1. 把 Biblia.app 拖到「应用程序」(Applications) 文件夹。
2. 第一次打开时，macOS 会提示无法验证开发者：请右键（或按住 Control 点击）Biblia -> 打开 -> 打开。
   如果没有"打开"按钮：系统设置 -> 隐私与安全性 -> 往下找到 "Biblia" -> 点「仍要打开」。
3. 只需第一次这样操作。需要 macOS 14 (Sonoma) 或更高版本。
圣经经文均为公有领域（详见应用内「Acerca de Biblia」）。
TXT
OUT="$ROOT/build/Biblia-$VERSION.dmg"
rm -f "$OUT"
hdiutil create -volname "Biblia $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$OUT"
ls -lh "$OUT"
