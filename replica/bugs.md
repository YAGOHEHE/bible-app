# Bugs encontrados (ola 4, TEST)

Resumen: 0 altas, 3 medias, 3 bajas. Sin clic ni teclado (accesibilidad denegada); todo salvo lo indicado se verificó con capturas y unit tests.

### BUG-001: el parser acepta capítulo 0
- Severidad: baja
- Flujo: F06 / F06-E1. Pantalla: S02
- Pasos: `ReferenceParser.parse("John 0")`.
- Esperado: error. Actual: `BibleRef(book 43, chapter 0)`. El `GotoResolver` sí lo rechaza con los recuentos de capítulos, así que el usuario no lo ve.
- Evidencia: test `gotoRejectsChapterZero` (withKnownIssue; quitar al arreglar).
- Estado: abierto

### BUG-002: cabeceras de columna paralela rotas con ventana estrecha + inspector Strong
- Severidad: media
- Flujo: F03 / F03-E2. Pantalla: S03 + S06
- Pasos: `-startTranslation KJV -startGoto "John 3:16" -startParallel YES -strongMode YES -openStrong G25 -windowWidth 640 -windowHeight 700` (la ventana se queda en 800 px, el mínimo).
- Esperado: cabeceras de versión legibles. Actual: "En/gli/sh", "R/V/1/9/0/9" apilados letra a letra; columnas de ~120 px con texto en 1-3 palabras por línea.
- Evidencia: replica/screens/test-narrow-strong.png
- Causa probable: tres columnas con ancho flexible sin mínimo; barra lateral (300) + inspector (~250) comen el espacio. Sugerencia: ocultar el inspector o pasar a intercalado por debajo de un ancho.
- Estado: abierto

### BUG-003: contraste bajo en la lista de libros y "Recientes" de la barra lateral
- Severidad: media (por verificar)
- Flujo: F07 / F07-H1. Pantalla: S02
- Pasos: abrir en tema claro; leer nombres de libro y "Recientes".
- Esperado: >= 4,5:1. Actual: gris ~#B0B0B0 sobre #F0F0F0, ~1,9:1 medido en pixeles; en oscuro ~2,7:1. Los títulos de la barra superior también salen grises, lo que sugiere que la captura se tomó con ventana inactiva; puede ser rendering de ventana no activa. Reverificar con ventana activa a mano.
- Evidencia: replica/screens/test-F04-strong.png, test-theme-dark.png, test-active-window.png
- Estado: abierto

### BUG-004: en 80 % el título de salmo queda sin escalar y desalineado
- Severidad: baja
- Flujo: F07 / F07-E1. Pantalla: S01
- Pasos: `set.fontScale 0.8`, CUV Salmo 23.
- Esperado: cabecera y sobrescrito coherentes con el texto. Actual: "大卫的诗。" centrado y el título "诗篇 23" en negrita grande a la izquierda; texto poético en el 80 % muy pequeño con mucho espacio vacío a la derecha (columna de poesía estrecha).
- Evidencia: replica/screens/test-font-80.png
- Estado: abierto

### BUG-005: la búsqueda lanzada en una versión sin esos caracteres no sugiere cambiar de versión
- Severidad: baja
- Flujo: F05 / F05-E1. Pantalla: S05
- Pasos: `-startTranslation KJV -startSearch 永生`.
- Esperado: pista como "hay 149 resultados en CUV". Actual: solo "Sin resultados… Prueba otra palabra, otra versión o amplía el alcance" (correcto pero genérico).
- Evidencia: replica/screens/test-F05-search.png
- Estado: abierto

### BUG-006: inspector Strong sin palabra de contexto y nombres de libro mezclan idiomas
- Severidad: media
- Flujo: F04 / F04-H1. Pantalla: S06
- Pasos: abrir G25 con CUV como versión activa: la cabecera no muestra «palabra»; las apariciones listan "马太福音 5:43" con texto inglés KJV; con KJV, sidebar en inglés bajo títulos de sección en español ("Antiguo Testamento"). Mezcla de idiomas de interfaz (español) y de contenido (por versión) sin indicación.
- Esperado: coherencia o etiqueta de versión en las apariciones. Actual: texto en KJV sin decirlo en la fila.
- Evidencia: replica/screens/test-narrow.png (entre capturas previas), test-F04-strong.png
- Estado: abierto
