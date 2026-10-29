# Paridad de funciones (replica-diff)

Método: `parity.py replica/features.csv` (must 3, should 2, could 1; partial = 0,5; las filas `skip` quedan fuera). Sin comparación de capturas (no hay capturas del original). Contrastado con el código de `App/Sources/BibliaApp` y con `App/Resources/bible.sqlite`.

## Puntuación

| Nivel | Contadas | Puntuación |
|---|---|---|
| **Global** | 64 | **73,6 / 100** |
| must | 25 | 25/25 hechas = **100 %** |
| should | 13 | 9,0 / 13 = 69,2 % |
| could | 26 | 0,5 / 26 = 1,9 % |

Todos los must-haves están hechos: es publicable como v1. El score global está penalizado por el bloque «could» (notas, resaltados, planes, audio, etc.), que es deliberadamente posterior a v1.

## Cambios en features.csv

- 4 filas de contenido (CUV, RV1909, KJV/ASV, KJV con Strong): `no` -> `yes`. Verificado: `bible.sqlite` trae CUV, RV1909, KJV (con Strong) y ASV, de unos 31 000 versículos cada una, todo dominio público; más 14 298 entradas de léxico y 777 401 palabras etiquetadas.
- «Esquemas de color»: `no` -> `partial` (hay sepia además de claro/oscuro, pero no esquemas elegibles por modo).
- «Gestor de versiones» y «Atajos de teclado»: la nota estaba rota en dos líneas (CSV corrupto, 82 líneas con 2 filas de 2 columnas); reparadas y notas actualizadas (atajos hechos: ⌘F ⌘L ⌘G ⇧⌘G ⌘[ ⌘] ⌘+ ⌘- ⌘0 ⌥⌘V ⌥⌘S ⌥⌘C ⌘I ⌘Y). Siguen `partial`.
- 14 filas con `priority=skip`: parity.py no las excluía (las contaba como could). Movidas a `clone=skip`, `priority=could`, con nota. Esto sube el score de 66,3 a 73,6. Es un cambio de columna `priority` fuera del brief; reversible.
- Sin cambios (confirmadas con el código): lectura, navegación, paralelo, Strong (incl. versículos relacionados), búsqueda (incl. «sin resultados»), historial automático, fuente/tema.

## Qué falta, en orden de construcción

Should:
1. Vista dividida con panel lateral (SecondSplit).
2. Mostrar/ocultar panel de comentario/original (CommentAndOriginal; depende de tener comentario/original, hoy no hay).
3. Tipografía mixta CJK/Latín con fuentes elegibles.
4. Gestor de versiones: importar módulos (botón deshabilitado «Próximamente»).
5. Atajos restantes (⌃⌘S, etc.).

Could, orden sugerido por valor/coste:
1. Historial manual / marcadores.
2. Resaltados con colores y notas del usuario.
3. Formato de copia personalizable.
4. Seleccionar versículo en el panel original desplaza la lectura.
5. Referencias cruzadas (datos abiertos TSK) y textos originales griego/hebreo con licencia abierta.
6. Planes de lectura, TTS (AVSpeechSynthesizer), importación local de módulos.
7. Resto (mapas, diccionario, devocionales, comentarios, morfología).

## Recomendación v1 para el grupo de la iglesia

Publicar la v1 con lo ya construido: lector, selector y recientes, ir a referencia (⌘L), paralelo 2-3 versiones sincronizado, gestor de versiones, búsqueda (chino/español/inglés), Strong con KJV, historial, ajustes. Cubre el 100 % de los must y la reseña principal de usuarios (modo paralelo).

Antes de repartir (no son paridad, sino calidad): corregir lo que reporte TEST (`replica/bugs.md`), nombre/icono propios (replica-brand) y decidir firma/notarización.

Para v1.1, por orden: marcadores/historial manual, resaltados y notas sencillas (lo que más echará de menos un grupo de estudio), copia con formato personalizable, y fuentes CJK/Latín elegibles. Dejar fuera de v1: cuentas, sincronización, red, comentarios y contenido con derechos de autor.

---

# Actualización v1.1 (Ola C)

Método: `parity.py replica/features.csv` tras contrastar las filas v1.1 con el código y las pruebas (ver `replica/test-plan.md`, sección v1.1). Se añadió una fila (versiones de dominio público extra: CUVT, BSB, WEB, BLM) y no se tocó ninguna otra columna.

## Puntuación v1.1

| Nivel | Contadas | Puntuación |
|---|---|---|
| **Global** | 65 | **77,7 / 100** (v1.0: 73,6) |
| must | 25 | 25/25 = **100 %** |
| should | 13 | 9,0 / 13 = 69,2 % (sin cambios) |
| could | 27 | 6,5 / 27 = 24,1 % (v1.0: 1,9 %) |

Filas verificadas como hechas en v1.1: seleccionar versículos y copiar (barra, menú contextual, ⌘C / ⌥⌘C), historial manual/marcadores, referencias cruzadas (OpenBible, 343 k), notas con Markdown, búsqueda de notas, resaltados por color en todas las versiones, versiones extra de dominio público. Los 25 must siguen completos; la subida viene del bloque «could» que la 1.0 dejaba fuera.

## Recomendaciones para la v1.2

Por valor/coste para un grupo de estudio:
1. **Planes de lectura importables** (por ejemplo el «Plan Lectura CCB»): progreso por día y desfase.
2. **Exportar notas** a Markdown/PDF (las notas ya son Markdown).
3. **Copia de seguridad de anotaciones** (fichero JSON/zip de `user.sqlite`, restaurable).
4. **Formato de copia personalizable** (plantilla `{libro} {ref} {texto}`).
5. **Lectura en voz alta** con las voces del Mac (AVSpeechSynthesizer).
6. **Compartir versículo como imagen** (hoja de compartir del sistema).
7. **Modo presentación** para proyector (texto grande, una versión).
8. **Etiquetas en notas** y filtro por etiqueta en el panel Notas.
9. **Diccionario de nombres y lugares** (Easton/Hitchcock, dominio público).
Arreglos antes de repartir: BUG-V11-03 (nombres de libro en tradicional para CUVT) y BUG-V11-02 (colocación de la barra de acciones con ventana estrecha o letra grande).
