# Biblia

Lector bíblico para macOS, gratuito y sin conexión, en **dos apps** con las mismas funciones (1.1):

| App | Interfaz | macOS | Datos de usuario |
|---|---|---|---|
| **Biblia** | SwiftUI | 14 (Sonoma) o superior | `~/Library/Application Support/Biblia/` |
| **Biblia Clásica** | AppKit, binario universal (Intel + Apple Silicon) | 10.13 (High Sierra) o superior | `~/Library/Application Support/Biblia Clásica/` |

Ambas comparten la capa `BibliaCore` (dominio y datos, sin concurrencia, desplegable en 10.13) y el mismo `bible.sqlite`. La clásica incorpora SQLite 3.54 (dominio público, módulo `CSQLite`) porque el del sistema en 10.13 no tiene UPSERT ni FTS5 trigram, e incrusta el runtime de Swift 5.0 para macOS < 10.14.4.

 Proyecto independiente: **no está afiliado a ninguna otra aplicación bíblica** y es una implementación propia (clean-room).

## Funciones
- Lectura por libro y capítulo, con párrafos, poesía y títulos; temas claro, oscuro y sepia; tamaño de letra ajustable.
- Versiones: 和合本 (CUV, simplificado) y 和合本繁體 (CUVT), Reina-Valera 1909, Biblia Libre (BLM, español), King James (1769), American Standard (1901), Berean Standard Bible (BSB) y World English Bible (WEB).
- Vista paralela de hasta tres versiones (columnas o intercalada).
- Modo Strong: KJV con números Strong y léxico hebreo/griego.
- Búsqueda de texto completo, "Ir a referencia" (p. ej. `Juan 3:16`, `约3:16`), historial y copia con referencia.
- Anotaciones (v1.1): pulsa un versículo para ver la barra de acciones (copiar, con referencia, anotar, marcador, referencias, comparar, Strong y 5 colores de resaltado); también por clic derecho y desde el menú «Versículo» (⌥⌘C, ⌥⌘H, ⌥⌘N, ⌘D). Resaltados, marcadores y notas van por referencia, así que se ven en todas las versiones y en la vista paralela.
- Notas con Markdown y autoguardado, y panel lateral «Libros | Buscar | Notas» con filtros por tipo, color y libro y búsqueda de texto.
- Inspector con pestañas Strong · Nota · Referencias (343 000 referencias cruzadas de OpenBible, ordenadas por votos).
- Los datos de usuario (historial, notas, resaltados, marcadores, ajustes) se guardan solo en tu Mac.

## Compilar desde el código
Requiere solo las Command Line Tools de Xcode (sin Xcode completo).

```
python3 data/build_bibles.py      # genera App/Resources/bible.sqlite a partir de las fuentes públicas
cd App && swift build && swift test
cd .. && scripts/make_app.sh      # -> build/Biblia.app (firma ad-hoc)
scripts/make_dmg.sh               # -> build/Biblia-<versión>.dmg
scripts/make_classic_app.sh       # -> build/Biblia Clásica.app (universal x86_64 10.13 + arm64 11, runtime Swift incrustado, firma ad-hoc)
scripts/make_classic_dmg.sh       # -> build/Biblia-Clasica-<versión>.dmg (reconstruye la app y verifica la firma)
```
La app clásica necesita las librerías Swift 5.0 de las Command Line Tools (`/Library/Developer/CommandLineTools/usr/lib/swift-5.0/macosx`, variable `SWIFT5_LIBS`).
La versión sale del fichero `VERSION` (1.1.2). El icono («Códice»: libro abierto con la cruz en el pliegue) se regenera con `scripts/make_icon.sh`, que produce `App/Icon/Biblia.icns`; `scripts/make_app.sh` lo copia al paquete. La app pesa unos 240 MB porque incluye las ocho versiones, el léxico Strong y las referencias cruzadas.

## Instalación
Biblia (macOS 14+): [`replica/INSTALAR.md`](replica/INSTALAR.md). Biblia Clásica (macOS 10.13+): [`replica/INSTALAR-CLASICA.md`](replica/INSTALAR-CLASICA.md); prueba en Mac antiguo: [`replica/PRUEBA-MAC-ANTIGUO.md`](replica/PRUEBA-MAC-ANTIGUO.md). La app no está notarizada: la primera vez hay que abrirla con clic derecho -> Abrir.

## Licencias de los textos
Todos los textos son de dominio público (detalle y fuentes en [`data/SOURCES.md`](data/SOURCES.md)):
CUV y CUVT, RV1909, KJV 1769 (con números Strong de eBible.org / Crosswire), ASV 1901, BSB, WEB y Biblia Libre (BLM), vía eBible.org y la API HelloAO. Referencias cruzadas: OpenBible.info, licencia **CC BY 4.0** (atribución: openbible.info; se muestra en «Acerca de»). Léxico Strong de OpenScriptures (dominio público). Estructura de la RV1909 adaptada de la Berean Standard Bible (dominio público). KJV: restricción de impresión en papel en el Reino Unido (letters patent); no afecta al uso digital. Código: usa GRDB.swift (MIT) y SQLite 3.54 (dominio público, incluido en la app clásica).
