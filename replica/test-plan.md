# Plan de pruebas: BibliaApp

Build: working tree sobre master (ola 4)  Fecha: 2026-10-29  Entorno: macOS 14+, datos incluidos (bible.sqlite), release ad-hoc (`scripts/make_app.sh`).

Método: replica-test. Automáticas = `cd App && swift test` (61 tests, 1 known issue) y `python3 data/test_bundle.py`. Manuales = lanzar la app con argumentos (`open build/BibliaApp.app --args -startTranslation … -startGoto … -strongMode YES -openStrong G25 -showHistory YES -startSearch … -startSearchOpenFirst YES -startParallel YES -startParallelLayout interleaved -showVersions YES -windowWidth N -windowHeight N`) y ajustes por `defaults write org.bibliaapp.reader set.theme|set.fontScale`, capturando con `screencapture -o -l <windowID>`. Accesibilidad denegada: NO se pudo hacer clic ni teclear.

Hooks de prueba añadidos en `UI/BibliaApp.swift` (solo argumentos de arranque): `startParallel`, `startParallelLayout`, `showVersions`, `windowWidth/windowHeight`.

| caso | flujo | tipo | pasos | esperado | auto | resultado |
| --- | --- | --- | --- | --- | --- | --- |
| F01-H1 | F01 | feliz | abrir con posición guardada | vuelve a KJV Juan 3:16 | unit (resumeRoundTrip, appStateFlow) + captura F01-* | pasa |
| F01-E1 | F01 | borde | versión guardada no instalada | cae a la primera disponible | unit (versionSetEdges, reconcile) | pasa; aviso al usuario no verificado visualmente |
| F01-E2 | F01 | borde | primera apertura | Génesis 1 | no | NO EJERCITADO (defaults reales ya existían) |
| F02-H1 | F02 | feliz | siguiente/anterior | capítulo cambia | unit (boundaryNavigation) | pasa; clic no ejercitado |
| F02-E1 | F02 | borde | último capítulo / extremos | salta de libro; desactivado en extremos | unit (chapterNavExtremes) | pasa |
| F03-H1 | F03 | feliz | paralelo 3 versiones | columnas/intercalado alineados | unit (john3AllPresent…) + capturas F03-* | pasa |
| F03-E1 | F03 | borde | versión sin versículo / fusionado | marcador, no se rompe | unit (asvOmitted…, numbers1_20Merged) | pasa |
| F03-E2 | F03 | borde | ventana estrecha 800 px + inspector | columnas legibles | captura narrow-strong | FALLA (BUG-002) |
| F04-H1 | F04 | feliz | palabra -> Strong G25 | inspector con lema y apariciones | unit + captura F04-strong | pasa |
| F04-E1 | F04 | borde | versión sin Strong | sugiere KJV | no | NO EJERCITADO |
| F05-H1 | F05 | feliz | buscar 永生 en CUV, abrir resultado | 149 resultados, versículo resaltado | unit (SearchGoto*) + captura F05-search-cuv | pasa |
| F05-E1 | F05 | borde | sin resultados | estado vacío | captura F05-search (KJV, 永生) | pasa (mensaje claro) |
| F05-E2 | F05 | borde | "peace/love" OR | resultados de ambos | unit (slashIsOr); captura F05-search-en | pasa |
| F06-H1 | F06 | feliz | ⌘L + referencia | salta | unit (examples, navigationRecordsJump) | pasa; atajo no pulsado |
| F06-E1 | F06 | borde | números chinos / rango / basura / capítulo fuera de rango | parsea o falla limpio | unit (TestPlanTests) | pasa; BUG-001 (parser acepta cap. 0, el resolver lo frena) |
| F07-H1 | F07 | feliz | tema claro/oscuro/sepia | colores coherentes | capturas theme-*, F01-*-light | pasa; BUG-003 contraste barra lateral |
| F07-E1 | F07 | borde | 80 % y 200 % | sin cortes | unit (fontScaleExtremes, settingsPersist) + capturas font-80/200 | pasa; BUG-004 |
| F07-E2 | F07 | borde | tema "sistema" en caliente | sigue al sistema | no | NO EJERCITADO |
| F08-H1 | F08 | feliz | hoja de versiones | lista, principal, ordenar | captura F08-versions + unit | pasa; clic no ejercitado |
| F08-E1 | F08 | borde | no desactivar la última | principal siempre activa | unit (versionSetEdges); casilla principal atenuada en captura | pasa |
| F09-H1 | F09 | feliz | abrir historial | lista agrupada Hoy/Ayer | captura F09-history + unit | pasa; clic en entrada no ejercitado |
| F10-H1 | F10 | feliz | copiar con formato | texto con referencia | unit (copyFormat, copyJohn316InThreeLanguages) | pasa; selección + ⌘C NO ejercitados |

Restauración: defaults y user.sqlite reales respaldados en /tmp y restaurados al terminar.

## v1.1 (Ola C)

Build: `build/Biblia.app` 1.1.0 (release ad-hoc). Automáticas: `cd App && swift test` (110 tests, 0 known issues) y `python3 data/test_bundle.py`. Manuales: argumentos de arranque `-startTranslation`, `-startGoto`, `-selectVerse 16`, `-annotate "16:yellow,17:bookmark,18:note"`, `-openNote "Rom 8:28"`, `-notePreview 1`, `-showRefs "John 3:16"`, `-sidebar notes`, `-startParallel YES/NO`, `-windowWidth/-windowHeight`, más `defaults write org.biblia.lector set.theme light|dark|sepia` y `set.fontScale -float 0.8|2.0` (con la app cerrada), capturas con `screencapture -o -l <windowID>` en `replica/screens/v11-test-*.png`. Accesibilidad denegada: no se pudo hacer clic, clic derecho ni teclear; esos pasos se cubren con unit tests de la lógica (`VerseActionTests`, `NotesTests`, `AnnotationTests`).

| caso | flujo | tipo | pasos | esperado | auto | resultado |
| --- | --- | --- | --- | --- | --- | --- |
| F11-H1 | F11 | feliz | seleccionar Jn 3:16 | barra con Copiar, Con ref., Anotar, Marcador, Referencias (23), Comparar, Strong y 5 colores | unit (actionsDependOnSelectionAndTranslation, strongAndCompareFromBar) + captura F12-highlight-parallel / theme-light-annot | pasa; clic real no ejercitado |
| F11-E1 | F11 | borde | versión sin Strong (CUV) | «Strong» no aparece | captura font200 (CUV) y unit | pasa |
| F11-E2 | F11 | borde | ventana 800 px + inspector; 80 % y 200 % | barra legible, sin cortes | capturas narrow-actionbar, font80/200 | pasa con BUG-V11-02 (tapa texto/inspector) |
| F11-H2 | F11 | feliz | menú Versículo (⌥⌘C, ⌥⌘H, ⌥⌘N, ⌘D) y menú contextual | acciones según contexto | unit (menuEnablementMatchesContext, contextMenuScopeOutsideSelection, copyPlainAndReferenceForSelection) | pasa; atajos no pulsados |
| F12-H1 | F12 | feliz | resaltar v16 en amarillo | visible en KJV, RV1909 y columna CUV | unit (highlightShowsInEveryTranslation) + capturas F12-highlight-parallel, F12-parallel-cuv, F12-parallel-light-zh | pasa |
| F12-E1 | F12 | borde | versículo fusionado | hereda cualquier resaltado | unit (mergedVerseShowsAnyOfItsHighlights) | pasa |
| F12-H2 | F12 | feliz | marcador en v17 | bandera naranja en el texto y en las 3 columnas | capturas F12-parallel-cuv, theme-*-annot + unit (bookmarkToggleOverSet) | pasa |
| F13-H1 | F13 | feliz | crear nota en Rom 8:28 | icono en el texto, pestaña Nota con la cita, «Guardada», fecha en español | unit (autosaveIsDebounced, severalNotesPerRangeAndSelection) + capturas F13-note-editor, F13-note-preview | pasa |
| F13-E1 | F13 | borde | cuerpo vacío / cambio de pestaña / eliminar | no crea nota vacía; guarda al salir; elimina | unit (emptyBodyDeletesAndNeverCreates, flushSavesOnTabSwitchAndLoad, deleteSelectedFlow) | pasa; teclear en vivo no ejercitado |
| F13-E2 | F13 | borde | Markdown inválido | vista previa nunca falla | unit (markdownPreviewNeverThrows) | pasa |
| F14-H1 | F14 | feliz | pestaña Referencias de Jn 3:16 | 23 referencias por votos con fragmento | unit (realDataJohn316, mergeOrdersByVotesAndDedupes) + captura F14-refs | pasa; clic para navegar no ejercitado (la lógica de navegación va por `goTo`) |
| F14-E1 | F14 | borde | destino ausente en la versión | fila sin romper | unit (rowsHandleMissingTargetVerses) | pasa |
| F15-H1 | F15 | feliz | panel Notas con 4-7 elementos | contadores Todo/Notas/Resaltados/Marcadores, orden bíblico, buscador | captura F15-notes-panel, theme-light-annot, theme-sepia-annot + unit (countsAndKindFilters, colorBookAndTextFilters, sortOrders) | pasa |
| F15-E1 | F15 | borde | actualizar tras cambios | lista refleja altas/bajas | unit (refreshAfterMutation, appStateBumpsVersionOnAnnotationChanges) | pasa |
| F15-E2 | F15 | borde | fechas con región distinta a la de la app | español | unit (DateTextTests) + captura | pasa tras BUG-V11-01 |
| F17-H1 | F17 | feliz | gestor de versiones con 8 versiones | CUV, RV1909, KJV, ASV, CUVT, BSB, WEB, BLM; aviso si hay más de 3 activas | captura F17-versions + unit (newTranslationsPresent) | pasa |
| F18-H1 | F18 | feliz | BLM (español), CUVT (繁體), BSB y WEB | texto en su idioma/escritura; 66 libros | unit (newTextsHaveTheirOwnScriptAndLanguage) + capturas F18-blm-es, F18-cuvt-trad, F18-bsb-web | pasa; BUG-V11-03 (nombres de libro CUVT en simplificado) |
| F19-H1 | F19 | feliz | icono de cruz | Finder/Dock | captura icon-cross-1024 / 32 / 16; el empaquetado copia `Biblia.icns` | pasa en el paquete (Dock no capturado) |
| F20-H1 | F20 | migración | base v1.0 (solo `history` y `search_history`) | se abre, conserva historial y búsquedas y añade las tablas nuevas | unit (V10ToV11MigrationTests, migrationV2PreservesV1) + prueba real con la base de usuario de v1.0 (12 entradas, 1 búsqueda → intactas, `integrity_check` ok) | pasa |
| F20-E1 | F20 | borde | reabrir | las migraciones no se repiten | unit (V10ToV11MigrationTests) | pasa |
| F21-H1 | F21 | tema | claro, oscuro, sepia con barra, notas, marcadores | contraste y colores de resaltado legibles | capturas theme-light-annot, theme-sepia-annot, F12-* (oscuro) | pasa |
| F21-E1 | F21 | borde | 80 % y 200 % con anotaciones | sin cortes | capturas font80-annot, font200-annot | pasa |
| F22-H1 | F22 | rendimiento | arranque con 240 MB de datos | ventana rápida | medición: 0,27 s en caliente, 3,0 s en frío | pasa |

Restauración: defaults (`org.biblia.lector`) y `user.sqlite` reales respaldados en /tmp y restaurados al terminar (comprobado byte a byte: la base con SHA-1 idéntico; defaults idénticos tras borrar las claves `ann.lastColor` y `set.theme` que añadieron las pruebas).
