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
