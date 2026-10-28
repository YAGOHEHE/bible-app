# Oleadas pendientes — BibliaApp

Cómo usar este archivo: abre Claude Code en `~/Projects/biblia-app` y pega **un bloque «Prompt» cada vez**,
en orden. Cada prompt le pide a Claude que delegue el trabajo en un subagente Sonnet, lo verifique y haga commit.
No lances el siguiente hasta que el anterior termine con todo en verde.

## Estado (2026-10-28)
| Paso | Estado |
|---|---|
| Ola 1 recon + datos · Ola 2 arquitectura + diseño | ✅ hecho (commits 758870e…) |
| 3.1 Lector S01/S02/S08 · 3.2 Paralela S03/S04 · Estructura de libro impreso | ✅ hecho (740c52d) |
| 3.3 Búsqueda S05 + «ir a» (⌘L) + fix espacios KJV/ASV | ⏳ lanzado; comprobar con el Prompt 0 |
| 3.4 Strong S06 + Historial S07 | Prompt 1 |
| 4a Test · 4b Diff (paridad) | Prompt 2 |
| 5 Marca + distribución al grupo | Prompt 3 (requiere tus decisiones) |

Reglas comunes que ya conocen los prompts: solo Command Line Tools (sin Xcode), `import Testing` (no XCTest),
nunca `Bundle.module`, BD empaquetada solo lectura, nada copiado de `/Applications/精读圣经.app`,
`App/Resources/bible.sqlite` no va a git (se regenera con `python3 data/build_bibles.py`).

---

## Prompt 0 — verificar y cerrar el paso 3.3 (búsqueda)
```
Estás en ~/Projects/biblia-app. Un subagente terminó (o dejó a medias) el paso de búsqueda S05 + barra «ir a» (⌘L)
+ arreglo de espacios KJV/ASV en data/build_bibles.py. Verifica sin rehacer trabajo:
1. cd App && swift build && swift test  (todo en verde)
2. python3 data/test_bundle.py  (en verde; si bible.sqlite no tiene el arreglo, ejecuta python3 data/build_bibles.py — usa caché, 0 peticiones)
3. sqlite3 App/Resources/bible.sqlite "select text from verses where translation_id='KJV' and book=43 and chapter=3 and verse=3"  → debe decir "him, Verily"
4. scripts/make_app.sh && open build/BibliaApp.app ; mira replica/screens/clone-S05.png si existe.
Si algo falla o falta, delega el arreglo en un subagente con model "sonnet" dándole el error exacto. Cuando todo esté
en verde: git add -A && git commit -m "Ola 3.3: búsqueda (S05) e ir a referencia" (con la línea Co-Authored-By habitual).
Resume en 5 líneas qué quedó y qué falta.
```

## Prompt 1 — paso 3.4: panel Strong (S06) + historial (S07)
```
Estás en ~/Projects/biblia-app (app macOS SwiftUI, clean-room de una app de Biblia). Delega este paso en UN subagente
con model "sonnet" pasándole este brief completo; luego verifica tú (swift build && swift test, python3 data/test_bundle.py,
scripts/make_app.sh, mira las capturas) y haz commit "Ola 3.4: Strong (S06) e historial (S07)".

BRIEF PARA EL SUBAGENTE:
Construye S06 (panel Strong/léxico) y S07 (historial de lectura). Lee primero replica/architecture.md, replica/recon.md
(S06, S07, estados y flujos), replica/features.csv, replica/design/{tokens.json,components.md (wireframe S06, inspector,
⌘I inspector, ⌥⌘S modo Strong, ⌘Y historial),Theme.swift.md} y el código existente en App/Sources/BibliaApp
(Data/Repositories.swift ya tiene LexiconRepository y lectura de verse_words; Domain/Reader.swift con ChapterBuilder y
la tabla layout; UI/Reader/ReaderView.swift; UI/Parallel/ParallelView.swift; Data/UserStore.swift con la tabla history).
Reutiliza, no reescribas.
Reglas: solo Command Line Tools (swift build / swift test; NO hay XCTest → import Testing); nunca Bundle.module
(usa BibleDatabase.bundledPath()); BD empaquetada solo lectura (DatabaseQueue); modo de lenguaje 5; AppState
@Observable @MainActor; sin colores literales en vistas de lectura (theme.palette); no tocar App/Resources/bible.sqlite
salvo regenerarlo con data/build_bibles.py; nada de /Applications/精读圣经.app. Mantén verdes todos los tests existentes.
Datos: solo KJV tiene Strong (translations.has_strongs=1). verse_words(translation_id, book, chapter, verse, idx, word,
strong) — frases etiquetadas son una fila («the world» = G2889), palabras sin número tienen strong NULL, y las palabras
NO concatenan byte a byte a verses.text: alinéalas con el texto mostrado buscando cada word en orden (tolerante a
puntuación/mayúsculas); si una palabra no se encuentra, sáltala sin romper el resto. lexicon(id 'G25'/'H430', lemma,
translit, pronunciation, definition, kjv_usage) — 14.298 entradas, todo verse_words.strong tiene entrada.
Construir:
1. Modo Strong (⌥⌘S, botón en barra, persistente): en traducciones con Strong, las palabras con número llevan el
   subrayado punteado del token strong-underline; hover → trazo continuo + cursor de enlace; clic → abre el inspector
   S06. En traducciones sin Strong el botón se desactiva con tooltip «Esta versión no tiene números Strong».
   Funciona en modo párrafos/poesía y en una-versión-por-línea, y en la columna KJV de la vista paralela.
2. S06 inspector (⌘I, .inspector de SwiftUI): lema en escritura original (fuente que soporte griego y hebreo; hebreo
   RTL), transliteración, pronunciación, definición, uso en KJV, número (G/H), y «Otras apariciones»: lista de
   versículos KJV con ese strong (limitada, p. ej. 200, con recuento total) — clic navega allí. Estados: vacío
   («Activa el modo Strong y toca una palabra»), palabra sin número, cargando.
3. S07 historial (⌘Y, hoja o sección): lista agrupada por día (Hoy, Ayer, fecha) de la tabla history con referencia
   en el idioma de la traducción, versión y tipo (pasar página / salto); clic navega; «Borrar historial» con
   confirmación; estado vacío. Deduplica entradas consecutivas iguales.
4. Arregla de paso: el lector de una sola versión etiqueta CUV Mt 18:10 como «10–11» porque trata cualquier hueco como
   fusión; usa la misma regla de fusión/omisión que Domain/Parallel.swift (Versification) también en el lector.
Tests (swift-testing): alineación palabra↔texto en Jn 3:16 KJV («loved»→G25, «the world»→G2889), palabra no
encontrada no rompe, lookup G25/H430, «otras apariciones» de G25 > 100, historial agrupado/deduplicado/borrado,
Mt 18:10 CUV sin «10–11».
Hecho = swift build && swift test en verde (pega el resumen), scripts/make_app.sh construye, la app abre; capturas con
screencapture -l <windowID> en replica/screens/clone-S06.png (Jn 3:16 KJV con inspector abierto en G25) y
clone-S07.png. Actualiza la columna clone de replica/features.csv para lo terminado. Informe: qué hiciste, archivos,
tests, capturas, huecos conocidos.
```

## Prompt 2 — Ola 4: test + diff (dos subagentes en paralelo)
```
Estás en ~/Projects/biblia-app. Lanza EN PARALELO dos subagentes con model "sonnet" con estos briefs; cuando acaben,
revisa sus informes, arregla (o delega) los bugs de severidad alta, y haz commit "Ola 4: test y paridad".

BRIEF A — TEST: Sigue el método de la skill replica-test (~/.claude/skills/synced/*/replica-test/SKILL.md, con
test-plan.md y bug-report.md de esa carpeta). Escribe replica/test-plan.md a partir de los flujos F01–F10 de
replica/recon.md; añade los tests unitarios que falten (swift-testing, import Testing; NO XCTest; solo Command Line
Tools) sin romper los existentes; haz una pasada manual: construye con scripts/make_app.sh, abre la app y, para cada
flujo, deja la app en el estado con `defaults write org.bibliaapp.reader …` (claves en UI/AppSettings.swift y
UI/AppState.swift) y captura con screencapture -l <windowID> en replica/screens/test-*.png; revisa las capturas
(textos cortados, contraste, chino/español/inglés, tema claro/oscuro/sepia, 80 % y 200 % de tamaño, ventana estrecha).
Registra cada fallo en replica/bugs.md con severidad (alta/media/baja), pasos y captura. No arregles nada de UI tú
mismo salvo tests; reporta. Nada de /Applications/精读圣经.app.

BRIEF B — DIFF: Sigue el método de la skill replica-diff (~/.claude/skills/synced/*/replica-diff/SKILL.md). Ejecuta su
parity.py sobre replica/features.csv (revisa antes que la columna clone refleje el código real: abre el código y
corrige yes/partial/no donde no cuadre, justificándolo en notes). Escribe replica/diff.md con la puntuación de
paridad (must/should/could), la lista de lo que falta en orden de construcción y una recomendación de qué entra en la
v1 para el grupo de la iglesia. No compares capturas del original (no tenemos capturas suyas; no las hagas).
```

## Prompt 3 — marca y distribución (necesita tus decisiones)
```
Estás en ~/Projects/biblia-app. Antes de delegar, pregúntame con opciones: (1) nombre de la app (propón 5 nombres
originales en chino/español que no se parezcan a «精读圣经», usando la skill replica-brand), (2) cómo repartirla al grupo:
firma ad-hoc (cada persona hace clic derecho → Abrir la primera vez; gratis) o cuenta Apple Developer (99 USD/año,
notarizada, sin avisos), (3) versión mínima de macOS de los miembros. Con mis respuestas, delega en un subagente
"sonnet": renombrar (bundle id, CFBundleName, textos), icono propio según replica/design/app-icon-brief.md (generado
como .icns con iconutil desde PNG hechos con código, sin copiar nada del original), scripts/make_app.sh con versión,
un DMG (hdiutil) y una página corta replica/INSTALAR.md para el grupo con capturas. Verifica y haz commit.
```
