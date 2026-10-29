# BibliaApp: componentes y comportamiento (marca provisional)

Base: HIG de macOS, SwiftUI (macOS 14+), `NavigationSplitView` (barra lateral), toolbar nativa, `.inspector` para el panel Strong, ventana `Settings` para S08. Tokens en `tokens.json`; mapeo a código en `Theme.swift.md`. Identidad propia: ningún elemento imita el original.

## 0. Decisiones transversales

- **Temas**: `light`, `dark`, `sepia` (papel). "Sistema" = light/dark según `colorScheme`. Sepia es una elección explícita del usuario y afecta solo a las zonas de lectura (lector, columnas paralelas, inspector); el cromo (toolbar, barra lateral, Ajustes) sigue la apariencia del sistema con `.preferredColorScheme(.light)` para el contenido sepia.
- **Fuente de lectura**: latín = New York (`.serif`), fallback Iowan Old Style, Georgia. CJK = Songti SC, fallback PingFang SC. Un solo `AttributedString` por versículo con atributo de idioma; la cascada pone los glifos CJK en Songti SC. Interlineado: 1,55 latín / 1,85 CJK (se aplica por versión/columna, ver abajo).
- **Escala de tamaño**: 80 %-200 % en pasos de 10 % (17 pt = 100 %; 180 % = 30,6 pt). Equivale al Dynamic Type de iOS: todo lo del lector (texto, número, título, huecos) escala por `fontScale`. Atajos ⌘+ / ⌘−, ⌘0 = 100 %. A 180-200 % el lector debe seguir sin recortes ni desbordes horizontales y la paralela pasa a columnas apiladas si ancho < 300 pt por columna.
- **Número de versículo**: superíndice (offset 0,38 em), 0,62 em, peso 600, dígitos tabulares, color `verse-number` (apagado), no seleccionable en copia salvo formato "con números".
- **Título de sección**: 0,92 em, 600, color `heading`, espacio antes 1,4 em / después 0,5 em. No va en mayúsculas.
- **Strong**: solo con modo Strong activo (interruptor en toolbar/menú Ver ⌘I abre inspector y activa modo). Palabra con Strong: subrayado punteado de 1 pt (`strong-underline`, trazo 1-2), a 2 pt bajo la línea base. Hover: subrayado a 1,5 pt continuo + cursor `pointingHand` + fondo `selection` al 40 %. Pulsada: fondo `selection`. Activa (la abierta en el inspector): fondo `selection` + subrayado continuo. Palabras sin datos Strong: sin subrayado, no interactivas.
- **Resaltado de búsqueda**: fondo `search-highlight`, texto `text-primary`, radio 3, sin cambiar peso. Se usa en S05 (fragmentos) y en el versículo de destino en S01 (versículo entero con `selection` + coincidencia con `search-highlight`, desaparece a los 4 s o al pulsar).
- **Versículo seleccionado**: fondo `selection`, radio `sm`, sin borde. Multiselección con ⇧-clic y ⌘-clic.
- **Paralela**: sin fondos de color ni barras laterales. Cada versión tiene un color de acento solo como color de texto (`version-1` azul, `version-2` verde, `version-3` ámbar; claro/oscuro/sepia, todos ≥ 4,5:1 sobre `background`, comprobado con `contrast.py`) que se usa para la sigla (cabecera de columna y prefijo de glosa). Columnas 4+ repiten 1-3. Separación con líneas finas `border`.
- **Foco**: anillo de 2 pt `focus-ring` (3:1 con el fondo) en todo control; el foco de teclado en el lector recorre versículos (↑/↓) y palabras Strong (⇥ / ⇧⇥ dentro del versículo, Intro abre inspector).
- **Estados vacío/error/cargando** (patrón común "Estado en línea"): icono SF Symbol 28 pt `text-muted`, frase de 1-2 líneas `text-secondary`, botón de acción opcional. Cargando: `ProgressView` pequeño tras 250 ms (evitar parpadeo) y esqueleto de líneas `border` en reposo. Error: icono `exclamationmark.triangle`, color `danger` solo en el icono (el texto sigue `text-primary`).
- **Movimiento**: 120 ms (hover/pulsado), 200 ms (paneles, inspector), 320 ms (cambio de capítulo con fundido). Con *Reducir movimiento* (`accessibilityReduceMotion`): sin animaciones de desplazamiento, fundido de 0 ms; `scrollTo` sin animación.
- **Interlineado por idioma**: como la paralela alinea versiones con distinta escritura, la fila del versículo toma la altura de su celda más alta; cada celda usa su propio interlineado (1,55 / 1,85) para no comprimir el chino.

## 1. Atajos de teclado (menús nativos con `.keyboardShortcut`)

| Acción | Atajo | Notas |
| --- | --- | --- |
| Buscar (S05) | ⌘F | Enfoca el campo; si ya abierto, selecciona todo |
| Ir a referencia (S02) | ⌘L | Recon pedía ⌘G; se usa ⌘L (como barra de direcciones). ⌘G queda como alias para "Siguiente coincidencia" en búsqueda. |
| Capítulo anterior / siguiente | ⌘[ / ⌘] y ← / → (con el lector enfocado y sin selección de texto activa) | Desactivado en Génesis 1 / Apocalipsis 22 |
| Tamaño de fuente | ⌘+ / ⌘− / ⌘0 | Pasos de 10 %, 80-200 % |
| Alternar paralela (S03) | ⌘\ | |
| Inspector Strong (S06) | ⌘I | Abre/cierra; con modo Strong |
| Modo Strong | ⌥⌘S | Activa el subrayado |
| Historial (S07) | ⌘Y | Hoja/ventana auxiliar |
| Versiones (S04) | ⌥⌘V | |
| Barra lateral | ⌃⌘S | Estándar del sistema |
| Ajustes (S08) | ⌘, | Ventana `Settings` |
| Copiar versículos | ⌘C | Formato de Ajustes; ⌥⌘C = copiar con referencia |
| Cerrar panel / cancelar | Esc | |

## 2. Componentes

Cada bloque: variantes, estados, tokens, accesibilidad, pantallas. Estados base: por defecto, hover, pulsado, seleccionado, desactivado, foco, vacío, cargando, error (se indican los que aplican).

### 2.1 Barra de navegación (toolbar)
- Variantes: normal (≥ 900 pt: título libro-capítulo, selector de versión, conmutador paralela, modo Strong, lupa, tamaño A−/A+), compacta (< 900 pt: botones agrupados en menú "···").
- Controles: `‹ ›` capítulo anterior/siguiente; botón título "Juan 3" (abre S02 como popover); menú de versión (abre S04); `Toggle` paralela; `Toggle` Strong; lupa.
- Estados: por defecto (fondo de toolbar del sistema), hover (`selection` 30 %), pulsado (`selection`), desactivado (`‹` en Génesis 1; texto `text-muted`), foco (anillo 2 pt).
- Tokens: texto UI `body` 13/600 para el título; iconos SF Symbols 15 pt `text-secondary`; activo (paralela/Strong) icono `accent`.
- A11y: `accessibilityLabel` "Capítulo anterior, Juan 2" / "Siguiente, Juan 4"; el título: "Libro y capítulo actual, Juan 3. Pulsa para cambiar". Valor del conmutador: "Vista paralela, activada".
- Usado en: S01, S03.

### 2.2 Línea de versículo
- Variantes: "una línea por versículo" (cada versículo bloque con hueco `verse_gap` 0,35 em) y "párrafo corrido" (versículos seguidos, salto de párrafo 0,9 em donde la versión lo marque).
- Estados: normal; hover (fondo `selection` 20 %); seleccionado (`selection`); resaltado por búsqueda/salto (`selection` + coincidencia `search-highlight`, se desvanece); foco de teclado (anillo 2 pt, radio `sm`); sin datos / error (nota en `text-muted` "Versículo no disponible en esta versión").
- Tokens: texto lectura 17 pt × escala, `text-primary`; número `verse-number`.
- A11y: cada versículo es un elemento accesible `"Versículo 16. <texto>"`; el número no se lee aparte (se oculta, su valor entra en el label del versículo). Acciones personalizadas: "Copiar versículo", "Copiar con referencia". Selección anunciada: "Versículo 16 seleccionado".
- Usado en: S01, S03, S05 (fragmentos).

### 2.3 Título de sección
- Variantes: normal; con enlace de referencia (could): referencia en `accent` 0,8 em tras el título.
- Estados: normal; hover del enlace (subrayado); foco.
- A11y: trait `isHeader` (nivel 2); capítulo = nivel 1.
- Usado en: S01 (y S03 si la versión lo trae, en cada columna).

### 2.4 Palabra con Strong
- Variante única: subrayado punteado (ver §0). Solo con modo Strong activo; si está apagado, texto plano.
- Estados: normal, hover, pulsada, activa (inspector abierto con ella), foco (anillo alrededor del run), desactivada = sin datos (sin subrayado).
- A11y: elemento "Botón: <palabra>, número Strong G25, griego". Acción por defecto abre inspector. Orden de lectura dentro del versículo se conserva. En VoiceOver el rotor "Palabras Strong" lista todas las del capítulo.
- Usado en: S01, S03, S06 (origen).

### 2.5 Vista paralela: Intercalado «Principal + glosas» y Columnas limpias
- **Intercalado (principal + glosas)**: la versión principal se lee como en el lector (títulos de sección, líneas de poesía sangradas, número de versículo una sola vez en superíndice, mismo `BlockView`). Bajo cada versículo, una línea por glosa: sangría 1,5 em, tamaño 0,82×, `text-secondary`, sigla en versalitas y negrita con el color de acento de la versión (solo texto). Sin tarjetas, fondos, barras laterales ni cabeceras de columna. Separación entre versículos 1 em. Versículo ausente en una glosa: la línea no se muestra; fusionado: «(20–21)» en `text-muted`; rango propio: prefijo `20–21` atenuado.
- **Glosas elegidas**: menú «Glosas» en la barra (visible en modo intercalado) con las versiones agrupadas por idioma (中文 / Español / English), con marca de verificación, sin la principal, máx. 3, orden de elección; también como sección «Glosas del modo intercalado» del gestor de versiones (S04). Persistido en `par.glosses`, aparte de las columnas. Sin glosas: aviso discreto «Sin glosas: solo se lee la versión principal» + botón «Elegir glosas». ⌥⌘G muestra/oculta todas las glosas (`par.glossesOn`).
- **Interacciones**: selección, barra de acciones (acoplada abajo), resaltados, marcadores, notas y Strong actúan sobre el versículo principal; clic en una glosa selecciona su versículo. Copiar (con referencia o plano) en este modo copia la principal + las glosas visibles.
- **Columnas**: texto sobre el fondo normal; línea fina `border` entre filas y línea vertical fina entre columnas; la identidad de la versión solo en la cabecera (sigla en su acento + idioma). Selección/resaltado/destello se pintan solo sobre el texto. Hueco: «—» `text-muted` sin caja.
- **Ventana estrecha**: Columnas cae a apilado (< 300 pt por columna) y el apilado usa el estilo glosas con las versiones activas.
- Estados: normal; versículo ausente en la principal (número atenuado + «—», sus glosas se mantienen); error (versión no instalada: estado en línea + botón «Abrir gestor de versiones»).
- A11y: cada glosa es un elemento «<versión>. Versículo N. <texto>»; cabeceras de columna con trait de encabezado; hueco: «Versículo 5 no existe en <versión>».
- Usado en: S03.

### 2.6 Cuadrícula de libros y capítulos
- Variantes: pestañas AT / NT (control segmentado) y sección "Recientes" (chips, máx. 6). Celdas de libro: nombre en el idioma de la versión (2 columnas en 360 pt; 1 línea, truncado medio); celdas de capítulo: botones cuadrados 36 pt, número tabular.
- Estados: normal, hover (`selection` 30 %), pulsado, seleccionado (`accent` fondo, `on-accent` texto), foco, vacío (sin recientes: sección oculta).
- A11y: "Juan, libro 43 de 66"; "Capítulo 3". Navegación con flechas en la cuadrícula.
- Usado en: S02.

### 2.7 Campo de referencia con análisis
- Variantes: popover con campo grande (17 pt) y lista de sugerencias.
- Estados: vacío (placeholder "Juan 3:16, 约3:16, John 3:16"); válido (vista previa debajo: "Juan 3:16 · Juan, capítulo 3, versículo 16"); no reconocido (borde `danger` 2 pt + texto "No reconozco esa referencia" y 3 sugerencias); fuera de rango (aviso "Juan solo tiene 21 capítulos, se abrió el 21"); foco.
- A11y: etiqueta "Ir a referencia"; resultado de análisis anunciado con `AccessibilityNotification.Announcement`. Intro confirma.
- Atajo: ⌘L. Usado en: S02.

### 2.8 Campo de búsqueda + chips de alcance
- Variantes: campo con lupa y botón limpiar; chips Todo / AT / NT / Libro… (control segmentado + menú de libro). Sugerencia permanente: "Usa / para buscar alternativas: paz/amor".
- Estados: vacío (muestra historial), escribiendo, sin resultados, cargando (indicador en el campo), consulta mal formada (mensaje debajo), versión sin índice (estado en línea).
- A11y: `searchable` nativo; contador de resultados anunciado ("12 resultados").
- Atajo: ⌘F. Usado en: S05.

### 2.9 Fila de resultado
- Variantes: referencia (negrita 13, `text-primary`) + fragmento (lectura 15 pt, coincidencias con `search-highlight`); en historial: referencia + etiqueta de origen + hora.
- Estados: normal, hover, seleccionada (`selection`), foco, versión no instalada (texto `text-muted` + icono).
- A11y: "Juan 3:16. <fragmento>. Coincidencia: amor". ↑/↓ navegan, Intro abre.
- Usado en: S05, S07.

### 2.10 Panel lateral (inspector)
- Variantes: Strong (v1), original (could). `.inspector` de SwiftUI; ancho ideal 320, colapsable; en ventana < 900 pt se presenta como hoja.
- Estados: abierto, cerrado, cargando, vacío ("Selecciona una palabra subrayada"), sin datos Strong, sin entrada en léxico.
- Fondo `surface`, borde izquierdo `border`.
- A11y: región "Inspector Strong"; al abrir, foco al encabezado. Esc cierra y devuelve foco a la palabra de origen.
- Atajo: ⌘I. Usado en: S03, S06.

### 2.11 Entrada de léxico
- Variantes: encabezado (número "G25" en pastilla `accent`/`on-accent`, palabra original 22 pt en fuente griega/hebrea del sistema ("Times New Roman" / "Arial Hebrew"), transliteración itálica), definición (13 pt, `text-primary`, inglés), "Versículos relacionados" (lista de filas 2.9).
- Estados: relleno; sin entrada ("Este número no tiene definición en el léxico incluido"); cargando.
- A11y: etiqueta "Strong G25, ágape, definición: …". Lectura del griego con `accessibilityLanguage` "el" / "he".
- Usado en: S06.

### 2.12 Fila de versión
- Variantes: con indicador Strong (pastilla "Strong" 11 pt `accent`), con idioma (ZH / ES / EN).
- Estados: activa (casilla marcada), inactiva, faltante/corrupta (icono `danger`, "Reinstalar"), desactivado (la última versión activa: casilla deshabilitada con ayuda "Debe haber al menos una versión activa"), arrastrar para ordenar (hover muestra asa).
- A11y: "Reina-Valera 1909, español, con números Strong, activa". Acciones: subir/bajar para ordenar sin arrastre.
- Usado en: S04.

### 2.13 Controles de Ajustes (deslizador, selector, interruptor)
- Nativos de macOS (`Slider`, `Picker(.segmented)`, `Toggle`). Deslizador de fuente: 80-200 % con marcas cada 10 %, valor numérico 13 pt a la derecha, previsualización en vivo (versículo de ejemplo en zh y es). Tema: Sistema / Claro / Oscuro / Papel (sepia) con miniaturas de 48×32 usando `background`+`text-primary` de cada tema. Fuentes: Latín y CJK en `Picker` con las listas de `tokens.json`.
- Estados: por defecto, desactivado, foco, valor fuera de rango (se limita y el campo vuelve al valor válido con un sonido del sistema).
- A11y: el deslizador anuncia "Tamaño de lectura, 180 por ciento"; `accessibilityAdjustableAction` en pasos de 10.
- Usado en: S08.

### 2.14 Estado vacío / error en línea
- Ver patrón en §0. Textos propios, ejemplos: "Aún no has leído nada" (S07), "Sin resultados para «x»" (S05), "Esta versión no incluye Daniel 3:24-30" (S01/S03).
- A11y: se lee como un grupo; el botón de acción se enfoca primero.
- Usado en: todas las pantallas.

### 2.15 Menú contextual de selección
- Opciones: Copiar, Copiar con referencia, Buscar «…», Abrir en paralela (si hay), Mostrar en Strong. Nativo (`.contextMenu`).
- Estados: normal, desactivado (sin selección).
- Usado en: S01, S03.

### 2.16 Barra lateral (NavigationSplitView)
- No figura en recon pero se usa como contenedor: secciones "Leer" (Libros AT/NT, Recientes), "Estudio" (Historial, Versiones). Ancho 240. Ocultable (⌃⌘S). Si la ventana es estrecha, la barra se oculta y los libros se eligen con ⌘L.
- Estados de fila: normal, hover, seleccionada (acento del sistema `Color.accentColor` o `accent` de tema), foco.
- Usado en: S01-S07.

## 3. Wireframes ASCII

### S01 Lector de capítulo (ventana 1100 × 720)
```
┌─────────────────────────────────────────────────────────────────────────────────────┐
│ ● ● ●  [‹][›]  [Juan 3 ▾]  [Reina-Valera 1909 ▾]      [⫴ Paralela][S Strong][A−A+][🔍] │ toolbar 52
├──────────────┬──────────────────────────────────────────────────────────────────────┤
│ LEER         │                                                                      │
│  Antiguo T.  │             Juan 3                    (chapter_title 1.6em)          │
│  Nuevo T.    │                                                                      │
│ RECIENTES    │             Nicodemo visita a Jesús   (section_heading, heading)     │
│  Juan 3      │             ¹Había un hombre de los fariseos…                         │
│  Salmos 23   │             ²Este vino a Jesús de noche…  (col máx 760, centrada)     │
│ ESTUDIO      │             ³Respondió Jesús y le dijo…                               │
│  Historial   │                                                                      │
│  Versiones   │             El nuevo nacimiento                                      │
│              │             ⁶Lo que es nacido de la carne…                           │
├──────────────┴──────────────────────────────────────────────────────────────────────┤
│  Juan 3 · Reina-Valera 1909 · 180 %                                    [‹ Juan 2] [Juan 4 ›] │ pie opcional
└─────────────────────────────────────────────────────────────────────────────────────┘
Vacío: Génesis 1 sin posición. Error: banner en línea sobre el texto.
```

### S03 Vista paralela con inspector
```
┌──────────────────────────────────────────────────────────────────────────────────────────┐
│ ● ● ●  [‹][›] [Juan 3 ▾]  [⫴ Paralela ✓]  [S Strong ✓]  [A−A+] [🔍]        [Inspector ▯] │
├────────┬─────────────────────────────┬─────────────────────────────┬─────────────────────┤
│ sidebar│ 和合本 · ZH     (parallel-1)│ Reina-Valera 1909 (parallel-2)│ INSPECTOR STRONG    │
│        │─────────────────────────────│─────────────────────────────│ G25  ἀγαπάω         │
│        │ ¹ 有一个法利赛人…            │ ¹ Había un hombre…          │ agapaō              │
│        │ ² 这人夜里来见耶稣…          │ ² Este vino a Jesús de noche│ ─────────────────── │
│        │ ³ 耶稣回答说…                │ ³ Respondió Jesús…          │ to love (in a social│
│        │ ⁴ — (hueco)                  │ ⁴ Nicodemo le dijo…         │ or moral sense)     │
│        │ ⁵ …                          │ ⁵ …                         │ Relacionados:       │
│        │                             │                             │  Juan 3:16 …        │
└────────┴─────────────────────────────┴─────────────────────────────┴─────────────────────┘
Las filas están alineadas por versículo; se expande a 3 columnas (parallel-3). Una sola versión: columna única + tarjeta "Añade otra versión".
```

### S05 Búsqueda (popover/hoja 560 × 560, o panel en la barra lateral)
```
┌──────────────────────────────────────────────────────┐
│ 🔍 [ paz/amor                               ✕ ]       │
│ (Todo) (AT) (NT) (Libro: Juan ▾)        12 resultados│
├──────────────────────────────────────────────────────┤
│ Juan 3:16                                            │
│ Porque de tal manera [amor]ó Dios al mundo…          │
│ Juan 14:27                                           │
│ La [paz] os dejo, mi [paz] os doy…                   │
│ …                                                    │
├──────────────────────────────────────────────────────┤
│ Inicial: "Recientes: paz, 爱, amor/gracia"  [Borrar]  │
│ Sin resultados: 🔍 "Sin resultados para «x»"          │
└──────────────────────────────────────────────────────┘
```

### S06 Panel Strong (inspector, ancho 320; con ventana estrecha sheet)
```
┌──────────────────────────────┐
│ Strong                  [✕]  │
│ ┌────┐                       │
│ │G25 │ ἀγαπάω                │  22 pt, fuente griega
│ └────┘ agapaō                │  transliteración itálica
│ ──────────────────────────── │
│ DEFINICIÓN (EN)              │
│ to love (in a social or      │
│ moral sense)                 │
│ ──────────────────────────── │
│ VERSÍCULOS RELACIONADOS (42) │
│  Juan 3:16   …amó Dios…      │
│  Juan 13:34  …amaos…         │
│ Sin datos: "Este versículo   │
│ no tiene números Strong"     │
└──────────────────────────────┘
```

## 4. Mapa pantalla -> componentes

| Pantalla | Componentes |
| --- | --- |
| S01 | 2.1, 2.2, 2.3, 2.4, 2.14, 2.15, 2.16 |
| S02 | 2.6, 2.7, 2.14 |
| S03 | 2.1, 2.2, 2.4, 2.5, 2.10, 2.14 |
| S04 | 2.12, 2.14 |
| S05 | 2.8, 2.9, 2.14 |
| S06 | 2.10, 2.11, 2.9, 2.14 |
| S07 | 2.9, 2.14 |
| S08 | 2.13 |

## 5. Accesibilidad resumida

- Contraste AA verificado (sección 6); el color nunca es la única señal: Strong lleva subrayado, selección fondo + contorno de foco, hueco paralelo lleva icono y texto.
- VoiceOver: números de versículo dentro del label del versículo; palabras Strong como botones con número; rotor propio de títulos (capítulo/sección).
- Tamaño: la escala 80-200 % es el equivalente a Dynamic Type; el cromo del sistema no escala, el lector sí; al cambiar el tamaño se conserva el versículo ancla.
- Movimiento reducido: ver §0.
- Objetivos: mínimo 24×24 pt en controles; palabras Strong con área de impacto ampliada 2 pt en vertical.

## 6. Informe de contraste (`python3 contrast.py tokens.json`)

Resultado: 126 pares, 0 fallos AA (exit 0). Mínimos: texto normal >= 4,5; UI >= 3.

```
  AAA   16.83:1  light-text-primary       on light-background     
  AAA   15.46:1  light-text-primary       on light-surface        
  AAA   14.67:1  light-text-primary       on light-parallel-1     
  AAA   15.01:1  light-text-primary       on light-parallel-2     
  AAA   14.86:1  light-text-primary       on light-parallel-3     
  AAA    9.07:1  light-text-secondary     on light-background     
  AAA    8.33:1  light-text-secondary     on light-surface        
  AAA    7.90:1  light-text-secondary     on light-parallel-1     
  AAA    8.09:1  light-text-secondary     on light-parallel-2     
  AAA    8.01:1  light-text-secondary     on light-parallel-3     
  AA     5.69:1  light-text-muted         on light-background     
  AA     5.23:1  light-text-muted         on light-surface        
  AA     4.96:1  light-text-muted         on light-parallel-1     
  AA     5.07:1  light-text-muted         on light-parallel-2     
  AA     5.03:1  light-text-muted         on light-parallel-3     
  AA     6.06:1  light-verse-number       on light-background     
  AAA   11.46:1  light-heading            on light-background     
  AAA    8.22:1  light-accent             on light-background     
  AA     5.56:1  light-verse-number       on light-surface        
  AAA   10.53:1  light-heading            on light-surface        
  AAA    7.55:1  light-accent             on light-surface        
  AA     5.28:1  light-verse-number       on light-parallel-1     
  AAA    9.99:1  light-heading            on light-parallel-1     
  AAA    7.16:1  light-accent             on light-parallel-1     
  AA     5.40:1  light-verse-number       on light-parallel-2     
  AAA   10.22:1  light-heading            on light-parallel-2     
  AAA    7.33:1  light-accent             on light-parallel-2     
  AA     5.35:1  light-verse-number       on light-parallel-3     
  AAA   10.12:1  light-heading            on light-parallel-3     
  AAA    7.26:1  light-accent             on light-parallel-3     
  AAA    8.22:1  light-on-accent          on light-accent         
  AAA   13.07:1  light-text-primary       on light-search-highlight 
  AAA   11.99:1  light-text-primary       on light-selection      
  AA     6.54:1  light-danger             on light-background     
  AA     6.00:1  light-danger             on light-surface        
  PASS   4.81:1  light-strong-underline   on light-background     ui
  PASS   3.65:1  light-border-input       on light-background     ui
  PASS   8.22:1  light-focus-ring         on light-background     ui
  PASS   4.20:1  light-strong-underline   on light-parallel-1     ui
  PASS   4.29:1  light-strong-underline   on light-parallel-2     ui
  PASS   4.25:1  light-strong-underline   on light-parallel-3     ui
  PASS   3.35:1  light-border-input       on light-surface        ui
  AAA   14.43:1  dark-text-primary        on dark-background      
  AAA   12.14:1  dark-text-primary        on dark-surface         
  AAA   10.70:1  dark-text-primary        on dark-parallel-1      
  AAA   10.41:1  dark-text-primary        on dark-parallel-2      
  AAA   10.58:1  dark-text-primary        on dark-parallel-3      
  AAA    9.61:1  dark-text-secondary      on dark-background      
  AAA    8.08:1  dark-text-secondary      on dark-surface         
  AAA    7.13:1  dark-text-secondary      on dark-parallel-1      
  AA     6.93:1  dark-text-secondary      on dark-parallel-2      
  AAA    7.05:1  dark-text-secondary      on dark-parallel-3      
  AA     6.25:1  dark-text-muted          on dark-background      
  AA     5.26:1  dark-text-muted          on dark-surface         
  AA     4.64:1  dark-text-muted          on dark-parallel-1      
  AA     4.51:1  dark-text-muted          on dark-parallel-2      
  AA     4.59:1  dark-text-muted          on dark-parallel-3      
  AA     6.71:1  dark-verse-number        on dark-background      
  AAA   11.38:1  dark-heading             on dark-background      
  AAA    8.17:1  dark-accent              on dark-background      
  AA     5.65:1  dark-verse-number        on dark-surface         
  AAA    9.57:1  dark-heading             on dark-surface         
  AA     6.87:1  dark-accent              on dark-surface         
  AA     4.98:1  dark-verse-number        on dark-parallel-1      
  AAA    8.44:1  dark-heading             on dark-parallel-1      
  AA     6.06:1  dark-accent              on dark-parallel-1      
  AA     4.84:1  dark-verse-number        on dark-parallel-2      
  AAA    8.21:1  dark-heading             on dark-parallel-2      
  AA     5.89:1  dark-accent              on dark-parallel-2      
  AA     4.92:1  dark-verse-number        on dark-parallel-3      
  AAA    8.35:1  dark-heading             on dark-parallel-3      
  AA     5.99:1  dark-accent              on dark-parallel-3      
  AAA    8.42:1  dark-on-accent           on dark-accent          
  AA     5.69:1  dark-text-primary        on dark-search-highlight 
  AAA    7.38:1  dark-text-primary        on dark-selection       
  AAA    7.72:1  dark-danger              on dark-background      
  AA     6.49:1  dark-danger              on dark-surface         
  PASS   8.44:1  dark-strong-underline    on dark-background      ui
  PASS   4.12:1  dark-border-input        on dark-background      ui
  PASS   8.17:1  dark-focus-ring          on dark-background      ui
  PASS   6.26:1  dark-strong-underline    on dark-parallel-1      ui
  PASS   6.09:1  dark-strong-underline    on dark-parallel-2      ui
  PASS   6.19:1  dark-strong-underline    on dark-parallel-3      ui
  PASS   3.46:1  dark-border-input        on dark-surface         ui
  AAA   11.04:1  sepia-text-primary       on sepia-background     
  AAA    9.81:1  sepia-text-primary       on sepia-surface        
  AAA   10.36:1  sepia-text-primary       on sepia-parallel-1     
  AAA    9.55:1  sepia-text-primary       on sepia-parallel-2     
  AAA    9.86:1  sepia-text-primary       on sepia-parallel-3     
  AAA    7.95:1  sepia-text-secondary     on sepia-background     
  AAA    7.06:1  sepia-text-secondary     on sepia-surface        
  AAA    7.46:1  sepia-text-secondary     on sepia-parallel-1     
  AA     6.87:1  sepia-text-secondary     on sepia-parallel-2     
  AAA    7.10:1  sepia-text-secondary     on sepia-parallel-3     
  AA     5.62:1  sepia-text-muted         on sepia-background     
  AA     5.00:1  sepia-text-muted         on sepia-surface        
  AA     5.28:1  sepia-text-muted         on sepia-parallel-1     
  AA     4.86:1  sepia-text-muted         on sepia-parallel-2     
  AA     5.02:1  sepia-text-muted         on sepia-parallel-3     
  AA     5.22:1  sepia-verse-number       on sepia-background     
  AAA    8.80:1  sepia-heading            on sepia-background     
  AA     6.55:1  sepia-accent             on sepia-background     
  AA     4.64:1  sepia-verse-number       on sepia-surface        
  AAA    7.82:1  sepia-heading            on sepia-surface        
  AA     5.82:1  sepia-accent             on sepia-surface        
  AA     4.90:1  sepia-verse-number       on sepia-parallel-1     
  AAA    8.26:1  sepia-heading            on sepia-parallel-1     
  AA     6.14:1  sepia-accent             on sepia-parallel-1     
  AA     4.52:1  sepia-verse-number       on sepia-parallel-2     
  AAA    7.61:1  sepia-heading            on sepia-parallel-2     
  AA     5.66:1  sepia-accent             on sepia-parallel-2     
  AA     4.67:1  sepia-verse-number       on sepia-parallel-3     
  AAA    7.86:1  sepia-heading            on sepia-parallel-3     
  AA     5.85:1  sepia-accent             on sepia-parallel-3     
  AAA    7.28:1  sepia-on-accent          on sepia-accent         
  AAA    8.29:1  sepia-text-primary       on sepia-search-highlight 
  AAA    7.63:1  sepia-text-primary       on sepia-selection      
  AA     6.23:1  sepia-danger             on sepia-background     
  AA     5.54:1  sepia-danger             on sepia-surface        
  PASS   4.56:1  sepia-strong-underline   on sepia-background     ui
  PASS   4.03:1  sepia-border-input       on sepia-background     ui
  PASS   6.55:1  sepia-focus-ring         on sepia-background     ui
  PASS   4.28:1  sepia-strong-underline   on sepia-parallel-1     ui
  PASS   3.94:1  sepia-strong-underline   on sepia-parallel-2     ui
  PASS   4.07:1  sepia-strong-underline   on sepia-parallel-3     ui
  PASS   3.58:1  sepia-border-input       on sepia-surface        ui

  126 pairs, 0 failing AA
```
