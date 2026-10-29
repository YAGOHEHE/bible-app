# Biblia

Lector bíblico para macOS (SwiftUI, macOS 14 o superior), gratuito y sin conexión. Proyecto independiente: **no está afiliado a ninguna otra aplicación bíblica** y es una implementación propia (clean-room).

## Funciones
- Lectura por libro y capítulo, con párrafos, poesía y títulos; temas claro, oscuro y sepia; tamaño de letra ajustable.
- Versiones: 和合本 (CUV, chino simplificado), Reina-Valera 1909, King James (1769) y American Standard Version (1901).
- Vista paralela de hasta tres versiones (columnas o intercalada).
- Modo Strong: KJV con números Strong y léxico hebreo/griego.
- Búsqueda de texto completo, "Ir a referencia" (p. ej. `Juan 3:16`, `约3:16`), historial y copia con referencia.
- Los datos de usuario (historial, ajustes) se guardan solo en tu Mac.

## Compilar desde el código
Requiere solo las Command Line Tools de Xcode (sin Xcode completo).

```
python3 data/build_bibles.py      # genera App/Resources/bible.sqlite a partir de las fuentes públicas
cd App && swift build && swift test
cd .. && scripts/make_app.sh      # -> build/Biblia.app (firma ad-hoc)
scripts/make_dmg.sh               # -> build/Biblia-<versión>.dmg
```
La versión sale del fichero `VERSION`. El icono se regenera con `swift scripts/make_icon.swift`.

## Instalación
Ver [`replica/INSTALAR.md`](replica/INSTALAR.md). La app no está notarizada: la primera vez hay que abrirla con clic derecho -> Abrir.

## Licencias de los textos
Todos los textos son de dominio público (detalle y fuentes en [`data/SOURCES.md`](data/SOURCES.md)):
CUV, RV1909, KJV 1769 (con números Strong de eBible.org / Crosswire) y ASV 1901, vía eBible.org y la API HelloAO. Léxico Strong de OpenScriptures (dominio público). Estructura de la RV1909 adaptada de la Berean Standard Bible (dominio público). KJV: restricción de impresión en papel en el Reino Unido (letters patent); no afecta al uso digital. Código: usa GRDB.swift (MIT).
