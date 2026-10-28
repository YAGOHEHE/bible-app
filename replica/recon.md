# Recon map: 精读圣经 (macOS, réplica clean-room)

Scope: lectura y estudio: leer capítulos, comparar versiones, Strong/léxico, búsqueda, historial, ajustes. Notas, resaltados (金句), planes, comentarios (注释), devocionales (灵修), audio/TTS (朗读), diccionario (辞典), preguntas bíblicas (圣经问答), mapas, cuentas, sincronización, WebDAV, transferencia de datos, compartir social y MP3 propios quedan FUERA de la primera versión (filas `could`/`skip` en features.csv).
For: la iglesia / grupo de estudio del usuario (compartida, gratuita).
Date: 2026-10-28

Regla clean-room: este documento describe funciones y patrones de UX. No se ha abierto, decompilado ni analizado el binario, ni sus .nib/.storyboard, ni su tráfico de red. No se copian textos, iconos ni nombre. Los nombres chinos de funciones se conservan entre paréntesis solo como referencia de trazabilidad.

## Sources

| # | fuente | URL / ubicación | notas |
| --- | --- | --- | --- |
| 1 | Ficha de App Store | https://apps.apple.com/us/app/%E7%B2%BE%E8%AF%BB%E5%9C%A3%E7%BB%8F/id969776780 | gratis, Referencia, iPhone/iPad/Mac (macOS 10.15+)/Vision, 4,9 de 5 (894 valoraciones), v3.6.2 (2025-04). Dice: lectura en voz alta, estudio, devocionales, diccionario, comparación de versiones, diccionario de originales, planes de lectura, preguntas bíblicas; muy personalizable (MP3, materiales, versiones y devocionales propios). Reseñas elogian: chino e inglés comparados en la misma página, muchos libros de referencia, lectura multilingüe, mapas, notas, resaltados, gratis |
| 2 | Ayudas incluidas en la app (documentación pública del propio producto) | Resources/help_original.txt, help_spiritual.txt, about.txt, sample.md | Datos originales de CBOL (léxico Strong); versiones con Strong en carpeta "bibles" y el usuario puede añadir las suyas (formato MySword); devocionales = carpeta con un archivo por día (MMDD.htm/txt); notas con Markdown |
| 3 | Registro de cambios (update.txt, 2016-2023) | Resources/update.txt | Mejor lista de funciones; resumida abajo |
| 4 | Instalación propia del usuario (sus datos, como evidencia del modelo) | bases SQLite de módulos, léxico, historial, notas, resaltados, planes, ajustes | Solo estructura y claves; sin copiar contenido protegido |
| 5 | Política de privacidad de la ficha | App Store | contacto para login; ID de dispositivo y diagnóstico (el clon no recoge nada) |

Resumen del changelog que informa el alcance: modo comparación (对照模式) y "cada versículo en su línea" (每节另起一行); títulos de sección (小标题) con enlaces a pasajes; nombres de personas y lugares subrayados que abren diccionario; números Strong por palabra con diccionario de originales (原文字典), "versículos relacionados", traducción literal (直译) y análisis de palabra (字汇分析); seleccionar un versículo en el panel original desplaza la lectura; búsqueda con "/" como OR e historial; referencias cruzadas (串珠) como enlaces; copia/compartir con formato personalizable; nombres de libros en el idioma de cada versión; tamaño de fuente; esquemas de color (uno por modo claro/oscuro) y color de comparación; panel dividido en iPad; recuerda la posición del comentario; planes con desfase de días; textos griego/hebreo como versiones.

## Core loop

Abrir la app y estar donde lo dejaste, leer un capítulo, comparar al instante con otra versión en paralelo y tocar una palabra para ver su número Strong y su significado original.

## Screens

Estados comunes a todas: modo oscuro (cada pantalla debe verse bien en claro y oscuro) y ventana estrecha/ancha.

| ID | pantalla | ruta / cómo se llega | propósito | componentes clave | estados |
| --- | --- | --- | --- | --- | --- |
| S01 | Lector de capítulo | pantalla principal; al abrir la app (retoma posición) | leer un capítulo de una versión | barra superior con libro-capítulo (abre S02) y versión (abre S04), lista de versículos con número, títulos de sección, palabras con Strong tocables, botones capítulo anterior/siguiente, selección de versículos + copiar | cargando (capítulo en lectura); relleno; vacío (primera apertura sin posición: Génesis 1); error: versión no instalada o libro ausente en esa versión; versículo sin datos Strong (palabra no tocable, sin subrayado); modo "una línea por versículo" vs párrafo corrido; versículo resaltado tras salto o búsqueda |
| S02 | Selector de libro/capítulo (+ libros recientes) | tocar el título de S01, ⌘G o atajo | elegir libro, capítulo y opcionalmente versículo | campo de referencia escrita ("Juan 3:16", "约3:16", "John 3:16"), sección "recientes", cuadrícula AT/NT, cuadrícula de capítulos, nombres en el idioma de la versión | vacío (sin recientes); relleno; referencia no reconocida (mensaje y sugerencias); capítulo fuera de rango (se ajusta o avisa) |
| S03 | Vista paralela / dividida | conmutador en la barra de S01 | comparar 2 o más versiones, misma referencia | columnas por versión alineadas por versículo, desplazamiento sincronizado, cabecera de versión por columna, color de comparación | una sola versión activa (invita a añadir otra); versión sin ese versículo (hueco marcado); cargando; versión no instalada; modo dividido con panel lateral (Strong/original) abierto o cerrado |
| S04 | Selector y gestor de versiones | menú de versión en S01 o ajustes | activar/ordenar versiones y ver/gestionar las instaladas | lista con nombre, idioma, marca "Strong", casilla de activa, orden, instalar/quitar módulos incluidos, importar local (could) | lista vacía (ninguna activa: obliga a elegir una); relleno; versión faltante/corrupta; importación fallida (could) |
| S05 | Búsqueda | ⌘F o icono de lupa | buscar texto en la versión activa | campo, selector de alcance (todo / AT / NT / libro), operador "/" como OR, historial, lista de resultados con referencia + fragmento resaltado, contador | inicial (muestra historial); historial vacío; cargando; resultados; sin resultados; consulta mal formada; versión sin índice; chino vs latín |
| S06 | Panel Strong / léxico | tocar una palabra con Strong en S01/S03 | ver el original y su significado | número Strong (G/H), palabra original, transliteración, definición (inglés, dominio público), lista de versículos relacionados, enlace para saltar | cargando; relleno; versículo sin datos Strong; número sin entrada en el léxico; panel colapsado (ventana estrecha) |
| S07 | Historial de lectura | menú o atajo | volver a lugares leídos | lista cronológica (más reciente primero), etiqueta de origen (cambio de página / salto), hora, borrar | vacío; relleno; entrada de un libro de una versión no instalada |
| S08 | Ajustes | ⌘, (ventana de ajustes de macOS) | personalizar lectura | tamaño de fuente (%), tema claro/oscuro/sistema, tipografía CJK/Latín, una línea por versículo, color de comparación, formato de copia, panel lateral | valores por defecto; fuente fuera de rango (limitada); previsualización en vivo |

Pantallas extra solo como funciones `could`/`skip` (sin ID S): notas, resaltados, planes, comentarios, devocionales, diccionario, mapas, audio, cuentas, copia WebDAV, transferencia de datos.

## Flows

```
F01 Retomar la lectura
    abrir app -> S01 (en la última posición)
    happy path clicks: 0
    edge: primera apertura (Génesis 1); versión guardada ya no instalada (cae a la primera disponible y avisa)

F02 Cambiar de capítulo
    S01 -> botón siguiente/anterior (o flecha del teclado)
    happy path clicks: 1
    edge: último capítulo del libro (pasa al libro siguiente), primero de Génesis / último de Apocalipsis (botón desactivado)
    alternativa por selector: S01 -> S02 (libro) -> capítulo = 3 clics

F03 Comparar versiones
    S01 -> activar paralelo (S03) -> elegir segunda versión (S04) 
    happy path clicks: 2 (si ya hay dos versiones activas) / 3 si hay que activar la segunda
    edge: versión sin ese libro o versículo; desplazamiento sincronizado al saltar de capítulo

F04 Tocar palabra -> Strong
    S01/S03 -> tocar palabra -> S06
    happy path clicks: 1
    edge: versión sin Strong (se sugiere KJV Strong); palabra sin entrada; seleccionar un versículo relacionado cambia de capítulo

F05 Buscar y abrir un resultado
    S01 -> ⌘F (S05) -> escribir + Intro -> clic en resultado -> S01 con el versículo resaltado
    happy path clicks: 2 (+ teclear la consulta)
    edge: sin resultados; "paz/amor" (OR); alcance por libro; consulta china sin espacios

F06 Saltar a una referencia escribiendo
    S01 -> ⌘G (S02) -> teclear "Juan 3:16" / "约3:16" / "John 3:16" + Intro -> S01 en el versículo
    happy path clicks: 0 clics de ratón con teclado (1 atajo + Intro); 2 con ratón
    edge: abreviaturas, números chinos ("约翰福音3:16"), rangos "3:16-18", referencia ambigua, libro inexistente

F07 Cambiar fuente y tema
    S01 -> ⌘, (S08) -> deslizador de fuente / selector de tema
    happy path clicks: 2
    edge: tamaño extremo; el tema "sistema" sigue los cambios del sistema en caliente

F08 Gestionar versiones
    S01 -> menú de versión (S04) -> activar/desactivar/ordenar (-> quitar si se permite)
    happy path clicks: 3
    edge: no se puede desactivar la última versión; versión corrupta

F09 Consultar el historial
    menú -> S07 -> clic en una entrada -> S01
    happy path clicks: 2

F10 Copiar versículos con formato
    S01 -> seleccionar versículo(s) -> ⌘C (formato de ajustes)
    happy path clicks: 1 clic + atajo
```

## Components

| componente | variantes | estados | usado en |
| --- | --- | --- | --- |
| Barra de navegación (libro-capítulo, versión, buscar) | normal, compacta | por defecto, pulsado, desactivado (extremos) | S01, S03 |
| Línea de versículo | número + texto; modo párrafo corrido | normal, seleccionado, resaltado por búsqueda/salto, hover | S01, S03, S05 |
| Título de sección | con enlace de referencia (could) | normal | S01 |
| Palabra con Strong (objetivo táctil) | subrayado punteado discreto | normal, hover, pulsada, activa | S01, S03 |
| Columna de versión | cabecera + lista alineada | normal, hueco, error, cargando | S03 |
| Cuadrícula de libros y capítulos | AT/NT, ordenación por libros recientes | normal, seleccionado | S02 |
| Campo de referencia con análisis | texto libre | vacío, válido, no reconocido | S02 |
| Campo de búsqueda + chips de alcance | AT/NT/libro | vacío, escribiendo, sin resultados | S05 |
| Fila de resultado | referencia + fragmento con coincidencia resaltada | normal, hover, seleccionada | S05, S07 |
| Panel lateral (inspector) | Strong, original (could) | abierto, cerrado, cargando, vacío | S03, S06 |
| Entrada de léxico | encabezado + definición + versículos relacionados | relleno, sin entrada | S06 |
| Fila de versión | con indicador Strong | activa, inactiva, faltante | S04 |
| Deslizador, selector segmentado, interruptor | estándar de macOS | por defecto, desactivado | S08 |
| Estado vacío / error en línea | icono + frase + acción | vacío, error | todas |
| Menú contextual de selección | copiar, copiar con referencia | -- | S01 |

## Inferred data model

Evidencia: estructuras observadas en la instalación del usuario; solo el esquema, nunca el contenido protegido.

```
Version (módulo de Biblia)  id, name, shortname, lang, langcode, date, isStrong, fileName
            evidence: tabla metadata(name,value) del módulo SQLite; catálogo con Name/FileName/Version/Language/IsStrong/DisplayName
            confidence: high

Verse       id, book, chapter, verse, scripture (texto con etiquetas Strong embebidas como <WG25>/<WH430> y morfología <WTG5656>; {…} = palabra original sin traducir)
            evidence: tabla Bible(id,Book,Chapter,Verse,Scripture)
            confidence: high
            clon: separar texto y tokens al importar (Token: verse_id, position, surface, strong_id) para tener objetivos táctiles sin parsear en vivo

SectionTitle  id, book, chapter, verse, text   (se muestra antes del versículo; opcional por versión)
            evidence: tabla Titles
            confidence: high

BookName    id, short_name, long_name, chapter_count  (por versión, idioma propio)
            evidence: tabla Books opcional; "nombres de libros en el idioma de cada versión"
            confidence: high

LexiconEntry  strong_id (5 dígitos, G/H), original_word, definition
            evidence: cbol.db tablas Greek y Hebrew por número Strong
            confidence: high
            clon: léxico Strong de dominio público (inglés)

ReadingHistory  id, version?, book_id, chapter_id, verse_id, tag ('翻页' cambio de página | '跳转' salto), time
            evidence: history.db Auto(BookId,ChapterId,VerseId,Tag,Time); Manual análogo
            confidence: high

SearchHistory  terms[]  (cadenas, orden por recencia)
            evidence: clave de ajustes SearchHistory (separada por saltos de línea)
            confidence: high

Settings    active_versions[] (orden), current_version, parallel_enabled, side_panel_visible, font_size_percent, theme, last_position (book, chapter, verse), recent_books[], scroll_offset
            evidence: claves Translations, CurrentBible, SecondSplitEnabled, BibleSecondViewState, CommentAndOriginal, FontSizePercent, BookId/ChapterId/VerseId, CatalogBookHistroy, RecordScrollTop, tema claro/oscuro
            confidence: high

(Fuera de v1, solo referencia)
Note        id, title, content (Markdown), tag, bible_name, verses, book_id, chapter_id, created, modified, is_deleted + Relation(note_id, book, chapter, from_verse, to_verse)
Highlight   book, chapter, verse, color_group, modified, is_deleted, tag
Plan        id, name, start_day, start_time + PlanDetail(plan_id, day, finished_numbers, state, updated)
Catalog     tablas Bible/Spiritual/Comment/Reference/Dictionary/Plan con id, name, file, version, language, is_strong, display_name
            confidence: high (evidencia directa), pero fuera de alcance
```

Relationships: Version 1-n Verse; Version 1-n SectionTitle; Version 1-n BookName; Verse 1-n Token (n-1 LexiconEntry por strong_id); ReadingHistory n-1 (book, chapter, verse) sin FK a Version; Settings 1 fila. Ver en el original: la posición se guarda por libro/capítulo/versículo y no por versión, lo que permite cambiar de versión sin perder el sitio.

Decisión de datos para el clon: una única base SQLite incluida (GRDB) con versiones de dominio público normalizadas a un mismo esquema, índice FTS y el léxico; estado del usuario (historial, ajustes) en una base separada en Application Support.

## Feature matrix

Ver `features.csv`. Must: 25, should: 13, could: 27, skip: 14 (79 en total).

## Out of scope (cannot or should not be cloned)

- Textos con derechos: RVR1995 (Sociedades Bíblicas Unidas), NBLH (Lockman), comentarios 精读本注释 / 综合解读 / 陈终道讲义, léxico chino CBOL (信望爱). El clon usa solo: 和合本 (CUV, simplificado, dominio público), Reina-Valera 1909, KJV, ASV, KJV con números Strong y diccionarios Strong de griego/hebreo públicos (definiciones en inglés).
- Edición propia del desarrollador (títulos, subrayado de nombres, puntuación revisada de su 和合本): no se copia.
- Red y servicios del original: servidores de descarga, cuentas (correo, teléfono, QQ), sincronización, códigos 口令, analítica, copia WebDAV, transferencia con Android/PC.
- SDKs de WeChat, QQ y Weibo; el compartir queda en copiar texto (y quizá el menú del sistema más adelante).
- Nombre, iconos, textos de interfaz y marca del original.
- Posibles extras (could): importar localmente módulos que el usuario ya posee, sin redistribuirlos.

## Size

Pantallas 8 (S01-S08), flujos 10 (F01-F10), entidades 7 en v1 (Version, Verse, Token, SectionTitle, BookName, LexiconEntry y estado de usuario: historial, ajustes, búsquedas). Stack: Swift 6 + SwiftUI + SwiftPM, macOS 14+, GRDB, una SQLite incluida. Talla: **M** (unas semanas) para la parte de lectura y estudio; L si se añaden notas, resaltados y planes.

Partes difíciles:
1. **Desplazamiento paralelo sincronizado** (S03): alinear versículos de versiones con distinta longitud, numeración distinta (por ejemplo salmos y versículos ausentes), conservar el ancla al cambiar de capítulo y de tamaño de fuente. Probable solución: una sola lista por versículo con N celdas, en lugar de N listas independientes.
2. **Renderizado de palabras con Strong y áreas táctiles** (S01/S06): texto SwiftUI con tokens tocables (AttributedString con enlaces o capa propia con `Text` concatenado), selección de texto conviviendo con el clic, rendimiento en capítulos largos (Salmo 119), VoiceOver.
3. **Búsqueda FTS para chino** (S05): FTS5 no segmenta chino; hace falta tokenizador por carácter o n-gramas, coincidencias resaltadas, operador "/" (OR) y alcance AT/NT/libro, sin degradar el latín.
4. Tipografía mixta CJK/Latín: elección de fuentes, interlineado, números de versículo, cursiva en KJV, tamaño porcentual coherente entre columnas.
5. Analizador de referencias multilingüe ("Juan 3:16", "约3:16", "John 3:16", abreviaturas, rangos) y tabla de alias de libros en zh/es/en.
6. Normalización de datos de dominio público (formatos distintos, etiquetas Strong, licencias y atribuciones) y empaquetado en una sola SQLite.

No se promete paridad perfecta: la primera versión replica el flujo de lectura y estudio, no el catálogo de contenidos del original.

Siguiente paso: `/replica-architect`.
