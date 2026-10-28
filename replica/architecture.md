# Arquitectura: BibliaApp (réplica clean-room de la app de lectura y estudio bíblico, macOS)

Fuentes: `replica/recon.md` y `replica/features.csv`. Nada del original se ha abierto ni copiado.

## Stack

| capa | elección | por qué |
| --- | --- | --- |
| lenguaje / UI | Swift 6.0.3 (modo de lenguaje 5, `swift-tools-version:5.9`) + SwiftUI | Única toolchain disponible (solo Command Line Tools); el modo 5 evita fricción de concurrencia estricta |
| mínimo | macOS 14 (Sonoma) | permite `@Observable`, `ContentUnavailableView`, `NavigationSplitView`, `inspector` |
| build | Swift Package Manager (target ejecutable) | No hay Xcode: `xcodebuild` no existe; `swift build` / `swift test` sí |
| base de datos | SQLite vía GRDB.swift **6.29.3** (exacta) | Una sola dependencia; FTS5 con tokenizador `trigram` (SQLite del sistema 3.43) |
| tests | `swift-testing` (`import Testing`, incluido en la toolchain 6.0 de CLT) | **XCTest no está disponible con solo CLT** (`no such module 'XCTest'`); Testing.framework sí y `swift test` lo ejecuta sin dependencias extra |
| estado | un `@Observable AppState` (`@MainActor`) | Ver "Estado" |
| ajustes | `UserDefaults` / `@AppStorage` | Valores simples (fuente %, tema, etc.) |
| datos de usuario | `~/Library/Application Support/BibliaApp/user.sqlite` (GRDB + migraciones) | Historial y búsquedas, separado del bundle de solo lectura |
| empaquetado | `scripts/make_app.sh` (.app a mano + `codesign -s -`) | Sin Xcode |

Sin red, sin cuentas, sin telemetría.

## Capas y módulos

```
UI (SwiftUI)  ->  AppState (@Observable, @MainActor)  ->  Repositories (structs, sync)  ->  GRDB DatabaseQueue
                                                          Domain (modelos, ReferenceParser: puro, sin I/O)
```

Carpeta `App/Sources/BibliaApp/`:

| carpeta | ficheros | contenido |
| --- | --- | --- |
| `Domain/` | `Models.swift`, `ReferenceParser.swift` | Translation, BookName, Verse, Heading, VerseWord, LexiconEntry, SearchHit, HistoryEntry, BibleRef; parser de referencias (puerto de `server.py`) |
| `Data/` | `BibleDatabase.swift`, `Repositories.swift`, `UserStore.swift` | Apertura solo lectura y localización del recurso; Translation/Verse(+headings, words)/Search/Lexicon repositories; UserStore con migrador |
| `UI/` | `BibliaApp.swift`, `AppState.swift`, `RootView.swift` | `@main App`, estado, shell con `NavigationSplitView` y stubs |

## Acceso a datos

- **Bundle** `bible.sqlite` (esquema fijo, `user_version=1`): `DatabaseQueue` con `Configuration.readonly = true`. Un queue (no pool) basta: lecturas de ms y evita que GRDB intente WAL sobre un fichero firmado. Si aparece contención, pasar a `DatabasePool(readonly)` solo cambia `BibleDatabase`.
- **Localización**: `BibleDatabase.bundledPath()` busca `BibliaApp_BibliaApp.bundle/Resources/bible.sqlite` en `Bundle.main.resourceURL` (.app), junto al ejecutable (`swift run`), `$BIBLIA_DB`, y por último `App/Resources/bible.sqlite` relativo al código fuente. **No usa `Bundle.module`** porque su accessor generado hace `fatalError` dentro del .app (busca en la raíz del .app, no en `Contents/Resources`). Si no hay fichero: `AppState.load = .missingData` y se muestra "Datos no encontrados".
- **Package**: el target tiene `path: "."` (raíz de `App/`), `sources: ["Sources/BibliaApp"]`, `resources: [.copy("Resources")]`, así el sqlite vive en `App/Resources/` sin copiarse manualmente. `Resources/.gitkeep` garantiza que la carpeta existe y el build no falla sin datos.
- **Repositories** (structs síncronos, `reader.read`): `capítulo = SELECT ... WHERE translation_id,book,chapter ORDER BY verse` (PK cubre el índice); `headings`; `words` (para Strong); `LexiconRepository.entry/relatedVerses`.
- **UserStore**: migración `v1` crea `history(id, translation_id, book, chapter, verse, kind page|jump, at)` y `search_history(query PK, at)`; índice por `at DESC`.

## Estado

Un único `@Observable AppState` (macOS 14) en lugar de `ObservableObject`: seguimiento de propiedades por vista (solo se re-renderiza lo que lee), sin `@Published`, y `@Bindable` para la selección de la barra lateral. Contiene: traducciones activas, versión actual, libro/capítulo, versículos y títulos cargados, versículo resaltado, palabra Strong seleccionada, estado de carga (`loading/missingData/failed/ready`). Se inyecta con `.environment(state)`. Los repositorios son síncronos y rápidos; se llaman desde `@MainActor` (capítulo <50 ms). Ajustes sencillos en `@AppStorage`; posición (`book/chapter/verse`, versiones activas, panel abierto) en `UserDefaults` (recon: la posición no depende de la versión).

## Navegación y ventanas

- `WindowGroup { RootView }` con `NavigationSplitView`:
  - **sidebar = S02**: libros AT/NT (nombres en el idioma de la versión desde `book_names`), cuadrícula de capítulos, campo de referencia (`ReferenceParser`), recientes.
  - **detail = S01 lector** o **S03 paralelo** (conmutador en la barra de herramientas), con títulos de sección y botones anterior/siguiente.
  - **inspector = S06 panel Strong** (`.inspector(isPresented:)`), colapsable.
- Barra de herramientas: campo de búsqueda (⌘F, `.searchable`) que muestra **S05** (lista de resultados) en el detail; selector de versión (S04, popover/menú); botón historial (S07, sheet o ventana).
- `Settings { SettingsView }` = **S08** (⌘,). Menús: ⌘G (ir a referencia), ⌘F, ←/→ capítulo.

## Pantallas -> ficheros

| pantalla | fichero (actual -> destino) |
| --- | --- |
| S01 Lector | `UI/RootView.swift` `ReaderView` -> `UI/Reader/ReaderView.swift`, `VerseRow.swift`, `StrongText.swift` |
| S02 Libro/capítulo | `RootView.swift` `BookSidebar` -> `UI/Navigation/BookSidebar.swift`, `GoToReferenceField.swift` |
| S03 Paralelo | stub `ParallelView` -> `UI/Parallel/ParallelView.swift` |
| S04 Versiones | -> `UI/Translations/TranslationPicker.swift` |
| S05 Búsqueda | stub `SearchResultsView` -> `UI/Search/SearchView.swift` |
| S06 Strong | stub `StrongPanel` -> `UI/Strong/StrongPanel.swift` |
| S07 Historial | stub `HistoryView` -> `UI/History/HistoryView.swift` |
| S08 Ajustes | stub `SettingsView` -> `UI/Settings/SettingsView.swift` |

## Flujos F01–F10: rutas / acciones

| flujo | acción en `AppState` / repositorio |
| --- | --- |
| F01 Retomar | `bootstrap()` lee posición de `UserDefaults` -> `reloadChapter()`; versión ausente -> primera disponible + aviso |
| F02 Cambiar capítulo | `nextChapter()/prevChapter()`: usa `chapterCount`; fin de libro pasa al siguiente; `UserStore.addHistory(kind:"page")` |
| F03 Comparar | `toggleParallel()`, `setActive(translations)`; `VerseRepository.chapter` por cada versión activa |
| F04 Strong | clic en palabra -> `selectStrong(id)` -> `LexiconRepository.entry` + `relatedVerses`; abre inspector |
| F05 Buscar | `SearchRepository.search(q, translationId, scope)` + `UserStore.addSearch`; clic -> `open(ref, highlight:)` |
| F06 Referencia | `ReferenceParser.parse` -> `open(BibleRef)`, `addHistory(kind:"jump")`; error -> mensaje + sugerencias |
| F07 Fuente y tema | `@AppStorage` en `SettingsView`; `.preferredColorScheme` |
| F08 Versiones | `TranslationRepository.all()` + lista activa en `UserDefaults` (mín. una) |
| F09 Historial | `UserStore.recentHistory()` -> `open(ref)`; `clearHistory()` |
| F10 Copiar | menú contextual/⌘C sobre selección -> `NSPasteboard` con plantilla `{libro} {ref} {texto}` |

## Rendimiento

- Capítulo < 50 ms: una consulta indexada por PK (~176 filas máx. + títulos); sin parseo (los tokens Strong ya están en `verse_words`); `LazyVStack` para Salmo 119. Medir con `os_signpost` en `reloadChapter`.
- Búsqueda: consulta de >=3 caracteres -> `verses_fts MATCH` con frase entre comillas (trigram sirve para chino y latín, insensible a mayúsculas); 1–2 caracteres (típico CJK) -> `LIKE '%x%'` sobre `verses` filtrado por `translation_id`; `/` = OR (varios términos). Límite 200 resultados; fragmento con «coincidencia».
- Paralelo: **una sola lista de filas por versículo** con N celdas (una por versión) -> el desplazamiento queda sincronizado por construcción y no hay N `ScrollView`. Ancla = `scrollPosition(id: verse)`; al cambiar de capítulo o de fuente se re-ancla al versículo actual. Versículos ausentes en una versión: celda "hueco". Unión ordenada de números de versículo entre versiones.
- Strong: `Text` concatenado/`AttributedString` con enlaces por palabra desde `verse_words`; cargar `words` solo si la versión tiene `has_strongs`.

## Empaquetado

`scripts/make_app.sh`: `swift build -c release`, crea `build/BibliaApp.app` (binario en `Contents/MacOS`, `BibliaApp_BibliaApp.bundle` y `GRDB_GRDB.bundle` en `Contents/Resources`, `Info.plist` con `org.bibliaapp.reader`, `LSMinimumSystemVersion 14.0`, `NSHighResolutionCapable`), `codesign --force --deep -s -`. El bundle de recursos incluye ~110 MB de sqlite. Identificador y nombre son provisionales hasta `replica-brand`. Distribución a la iglesia: ad-hoc, hace falta clic derecho -> Abrir la primera vez (sin notarización).

## Partes que muerden

- XCTest ausente con CLT -> usar `import Testing`.
- `Bundle.module` falla en el .app -> localizador propio.
- Doble niveles de fuente CJK/Latín y cursiva KJV.
- FTS `trigram` ignora términos <3 caracteres -> el fallback LIKE.
- Numeración distinta entre versiones (Salmos, versículos ausentes) -> unión por número, huecos visibles.
- FTS: columnas UNINDEXED se devuelven como texto; comparar con `translation_id` y convertir book/chapter/verse con `CAST`.

## Orden de construcción (cortes verticales finos)

1. **Lector** (hecho a nivel esqueleto): bootstrap, sidebar de libros, capítulo en texto plano, estado "datos no encontrados". Siguiente: S02 completa (cuadrícula, capítulos), prev/next, títulos, resume (F01, F02), copiar (F10), ajustes de fuente/tema (F07).
2. **Paralelo / versiones**: S04 + S03 con lista única por versículo, huecos, ancla (F03, F08).
3. **Búsqueda / referencias**: `GoToReferenceField` (F06), S05 con FTS/LIKE/OR/alcance, historial de búsquedas, resaltado al abrir (F05).
4. **Strong / historial**: render de palabras tocables, inspector S06, versículos relacionados (F04), S07 (F09).
5. Fuera de v1: notas, resaltados, planes, audio, etc. (ver `features.csv`, filas `could`/`skip`).
