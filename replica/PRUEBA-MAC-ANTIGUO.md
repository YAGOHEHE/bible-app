# Prueba de Biblia Clásica en un Mac antiguo real

Objetivo: comprobar en un Mac **Intel** con **macOS 10.13 (High Sierra), 10.14 (Mojave) y 10.15 (Catalina)** lo que no se puede probar en el Mac de desarrollo (macOS 14, Apple Silicon). Repite la lista en cada versión disponible y anota el resultado.

Material: `Biblia-Clasica-1.1.2.dmg`. Mac: ______  macOS: ______  Fecha: ______  Tester: ______

## Riesgos conocidos (qué vigilar)
1. **Runtime de Swift incrustado**: el binario x86_64 se compiló con Swift 6.0.3 pero enlaza las librerías Swift **5.0** incluidas en `Contents/Frameworks` (macOS < 10.14.4 no trae runtime de Swift). Si hay un cierre al arrancar con `dyld: Library not loaded` o `Symbol not found`, es esto.
2. **Enlaces débiles**: `Combine` y `libswift_Concurrency` están enlazados como débiles (no existen en 10.13/10.14; Concurrency solo desde 10.15). El código no debería usarlos en esas versiones; un cierre con `Symbol not found: ...Concurrency` o `Combine` indicaría un uso accidental.
3. **Repintado**: en 10.13/10.14 el lector puede quedarse con texto «viejo» tras cambiar tema, tamaño o capítulo (se aplicó una corrección de repintado; verificar que no hay restos ni zonas sin dibujar).
4. **Tema oscuro**: en 10.13 no hay modo oscuro del sistema; es el tema propio de la app.

## Checklist
Marca cada casilla; si falla, anota el síntoma y la versión de macOS.

### A. Arranque
- [ ] **A1. Abrir (Gatekeeper)**: arrastrar a Aplicaciones, clic derecho -> Abrir -> Abrir. *Esperado*: aviso de desarrollador no identificado; tras Abrir, la app arranca. (Alternativa: Preferencias del Sistema -> Seguridad y privacidad -> General -> «Abrir de todos modos».)
- [ ] **A2. Primera ventana**: aparece una ventana con barra lateral de libros y el lector con un capítulo (primera vez: Juan 3). Sin cierre, sin pantalla en blanco. Tarda menos de ~5 s.
- [ ] **A3. Icono y nombre**: Dock muestra la cruz latina; menú de la app dice «Biblia Clásica».

### B. Lectura
- [ ] **B1. Lector zh**: elegir 和合本 -> texto chino legible, versículos numerados (superíndices), títulos de sección.
- [ ] **B2. Lector es**: Reina-Valera 1909 -> acentos y ñ correctos.
- [ ] **B3. Lector en**: King James -> texto inglés correcto.
- [ ] **B4. Poesía**: Salmos 23 -> líneas con sangría de poesía, no un párrafo corrido.
- [ ] **B5. Anterior/siguiente**: ← / → (y botones) cambian de capítulo, también entre libros (Juan 21 -> Hechos 1).
- [ ] **B6. Ir a (⌘L)**: escribir `约3:16` -> salta a Juan 3 y destaca el versículo 16. Repetir con `Juan 3:16` y `John 3:16`.
- [ ] **B7. Tamaño de letra**: 80 % y 200 % -> el texto se redimensiona sin solapamientos ni recortes; 100 % restaura.
- [ ] **B8. Temas**: claro, sepia y oscuro. En **10.13** el oscuro es el propio de la app (fondo y texto, barra lateral coherentes); en **10.14+** además sigue la apariencia del sistema. Sin restos de color tras cada cambio (riesgo 3).

### C. Paralela y estudio
- [ ] **C1. Columnas paralelas**: ⌥⌘P (o menú) -> 2-3 versiones lado a lado, alineadas por versículo.
- [ ] **C2. Principal + glosas**: modo glosas con versión principal y glosas por idioma (zh/es/en); se actualiza al cambiar de capítulo.
- [ ] **C3. Búsqueda 永生**: ⌘F, `永生` -> resultados con el término resaltado; clic en un resultado salta al versículo.
- [ ] **C4. Búsqueda gracia**: `gracia` en RV1909 -> resultados (comprueba FTS5 trigram integrado).
- [ ] **C5. Strong G25**: modo Strong en KJV; clic en una palabra con número / buscar `G25` -> el inspector muestra el léxico de ἀγαπάω.
- [ ] **C6. Referencias cruzadas**: Juan 3:16 -> pestaña Referencias lista versículos relacionados; clic navega.
- [ ] **C7. Historial**: ventana Historial muestra los capítulos leídos, agrupados por día; clic navega; «Borrar historial» pide confirmación y **Esc cancela**.

### D. Anotaciones
- [ ] **D1. Selección**: clic en un versículo lo selecciona; clic en otros añade a la selección (acumulativa); clic fuera / Esc la limpia.
- [ ] **D2. Barra de acciones**: aparece al seleccionar; copiar, copiar con referencia, anotar, marcador, referencias, comparar, Strong y 5 colores funcionan.
- [ ] **D3. Resaltado**: aplicar un color y «Quitar».
- [ ] **D4. Marcador**: ⌘D añade/quita marcador.
- [ ] **D5. Nota**: escribir una nota (Markdown), se autoguarda; aparece el lápiz junto al versículo.
- [ ] **D6. Persistencia**: salir con ⌘Q y reabrir -> resaltados, marcadores y notas siguen ahí (también al cambiar de versión).
- [ ] **D7. Panel Notas**: pestaña «Notas» en la barra lateral: lista, filtros por tipo/color/libro, búsqueda; clic en una fila salta al versículo.
- [ ] **D8. Reanudar**: salir y reabrir -> vuelve al mismo libro, capítulo, versión, tema y tamaño.

## Si se cierra o falla
1. **Informe de bloqueo**: abre **Consola** (Aplicaciones -> Utilidades) -> en la barra lateral **Informes de bloqueo** (en 10.13/10.14: «Informes de diagnóstico») -> busca `Biblia Clasica`. O en Finder: Ir -> Ir a la carpeta -> `~/Library/Logs/DiagnosticReports/` y localiza `Biblia Clasica_*.crash`. Envía el fichero completo.
2. **Línea de arranque con SQLite**: la app escribe al iniciar un mensaje como
   `Biblia Clásica 1.1.2 — SQLite 3.54.1 upsert=true fts5-trigram=true`.
   Para verla: abre **Consola**, pulsa **Iniciar** (flujo en vivo), escribe `SQLite` en el filtro de búsqueda, abre la app. Debe decir `upsert=true fts5-trigram=true`; si dice `false` (o un error), la búsqueda/anotaciones fallarán: adjunta la línea completa.
3. Si no abre nada, lanza desde Terminal: `"/Applications/Biblia Clásica.app/Contents/MacOS/Biblia Clasica"` y copia la salida.
4. Anota: modelo de Mac, macOS exacto (Acerca de este Mac), pasos para reproducir y, si es posible, captura de pantalla.
