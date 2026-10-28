# Prompt: recuperar la estructura del texto (párrafos, poesía, títulos)

> Pégalo tal cual en una sesión de Claude Code abierta en `biblia-app/`.

---

Ahora la app guarda la Biblia como versículos sueltos y el lector los muestra uno tras otro. Quiero que se lea como un libro impreso: párrafos de prosa con los números de versículo en superíndice dentro del texto, poesía en líneas sangradas y títulos de sección con su jerarquía. Hay que regenerar `App/Resources/bible.sqlite` y adaptar el lector.

## Contexto: cómo se organiza un libro bíblico

El estándar del sector es USFM, y las fuentes que usamos (HelloAO y eBible) derivan de él. Cada capítulo tiene **dos jerarquías que se cruzan**:

1. **Referencias**: libro → capítulo (`\c`) → versículo (`\v`). Sirven para citar, buscar y enlazar Strong. No dicen nada de cómo maquetar.
2. **Maquetación**: bloques que pueden empezar en mitad de un versículo y abarcar varios.
   - Títulos: `\ms` (división mayor, p. ej. "LIBRO PRIMERO" en Salmos), `\s1`/`\s2` (sección), `\d` (sobrescrito de salmo: "Salmo de David", que forma parte del texto), `\r` (referencias paralelas bajo un título).
   - Prosa: `\p` (párrafo con sangría), `\m` (párrafo sin sangría, continuación tras una cita poética), `\pmo` (carta o discurso incrustado).
   - Poesía: `\q1`, `\q2`, … (una línea con nivel de sangría N), `\qr` (alineada a la derecha, p. ej. "Selah"), `\b` (línea en blanco entre estrofas).
   - Listas: `\li1`, `\li2` (genealogías, listados de Números o Crónicas).

Regla clave: **un versículo puede repartirse entre varios bloques** (por ejemplo, la mitad en prosa y la otra mitad en un `\q1`) y **un bloque contiene varios versículos**. Por eso la maquetación no cabe en una columna de `verses`: necesita su propia tabla.

## Qué hay en las fuentes (ya comprobado)

Los JSON de HelloAO están en caché en `data/cache/*.complete.json`. Su esquema es `ChapterContent = heading | line_break | verse | hebrew_subtitle`. El contenido de un verso es `string | {text, poem?: nivel, wordsOfJesus?} | {noteId}`. En la práctica también aparecen `{lineBreak: true}` dentro del verso.

| Versión | Títulos | `line_break` entre versos (= párrafo) | Saltos/poesía dentro del verso | Otros |
|---|---|---|---|---|
| CUV 和合本 | 2585 | 5951 | 18593 | |
| KJV | 36 + 116 `hebrew_subtitle` | 4844 | 2091 | 2970 `¶` = párrafos clásicos de la KJV |
| ASV | 116 `hebrew_subtitle` | 5026 | 10883 | |
| RV1909 | 0 | 1189 (uno por capítulo, es decir, nada) | 0 | |

`data/build_bibles.py` ahora **tira** los `line_break`, convierte los saltos y la poesía en espacios y borra los `¶`. Hay que dejar de hacer eso.

**RV1909 no tiene estructura en ninguna fuente libre.** Lo comprobé en el USFM de eBible (`https://eBible.org/Scriptures/spaRV1909_usfm.zip`): trae un `\p` por capítulo y nada más, aunque sí incluye Strong (`\w …|strong="H…"\w*`). Para RV1909 hay que **tomar prestada la estructura** de la Berean Standard Bible (dominio público): `https://eBible.org/Scriptures/engbsb_usfm.zip`. Sus cifras: 12273 `\m`, 16281 `\b`, 11562 `\q1`, 12550 `\q2`, 3017 `\s1`, 117 `\d`, 1343 `\li1`.

## Qué hacer

### 1. Esquema (`schema_version` = 2)

- `verses` no cambia: `text` sigue siendo texto plano en una línea. Así no se rompen FTS, Strong, la búsqueda ni las referencias.
- Tabla nueva `layout`:
  ```sql
  CREATE TABLE layout(translation_id TEXT NOT NULL, book INTEGER NOT NULL, chapter INTEGER NOT NULL,
                      seq INTEGER NOT NULL,          -- orden dentro del capítulo
                      kind TEXT NOT NULL,            -- 'p' | 'm' | 'q' | 'li' | 'b' | 'pmo' | 'qr'
                      level INTEGER NOT NULL DEFAULT 1,
                      verse INTEGER NOT NULL,        -- versículo al que pertenece el trozo
                      text TEXT NOT NULL,            -- trozo de texto de ese versículo dentro de este bloque
                      PRIMARY KEY(translation_id, book, chapter, seq));
  ```
  Cada fila es un **trozo de versículo dentro de un bloque**. Una fila con un `kind` de bloque abre un bloque nuevo, y las siguientes del mismo bloque usan `kind='+'` (continuación). También vale cualquier otra codificación equivalente que sea más limpia. Tiene que cumplirse que, por cada versículo, la concatenación de sus trozos sea igual a `verses.text`, salvo espacios.
- `headings` gana una columna `kind TEXT` con los valores `'ms' | 's1' | 's2' | 'd' | 'r'`. Los `hebrew_subtitle` pasan a ser `d`.

### 2. `data/build_bibles.py`

- **HelloAO (CUV, KJV, ASV):**
  - `line_break` a nivel de capítulo → el siguiente versículo abre un párrafo `p`.
  - `{text, poem: n}` → línea `q` de nivel `n`. Un `lineBreak` dentro del verso → nueva línea, con el mismo nivel si estamos en poesía y como párrafo si no.
  - Notas (`noteId`) → se descartan, como hasta ahora.
- **KJV:** cada `¶` abre un párrafo. Si choca con un `line_break`, gana el `¶`.
- **RV1909, plantilla BSB:**
  - Parsear el USFM de la BSB a "estructura por versículo": en qué tipo de bloque empieza cada versículo, si es poético y a qué nivel.
  - Como el texto español no se puede partir por donde la parte el inglés, se aplica **por versículos enteros**. Si un bloque de la BSB empieza en mitad del versículo N, el corte se mueve al versículo N+1. Un versículo poético de la BSB es una línea `q` con su nivel.
  - **No copiar los títulos `\s` en inglés.** Los `\d` tampoco se copian: en la RV1909 el sobrescrito ya va dentro del versículo 1.
  - Hay que tener en cuenta las diferencias de versificación entre BSB y RV1909: si un versículo no existe en la plantilla, se trata como prosa continua.
  - Guardar en `meta` la clave `structure_source:RV1909 = 'BSB (adaptada por versículo)'` y ponerlo en `data/SOURCES.md` junto con la licencia.
- Descargar los zips de eBible a `data/cache/`, como el resto de fuentes.

### 3. App

- `Models.swift`: añadir `LayoutPiece` y `Heading.kind`.
- `Repositories.swift`: cargar la maquetación de un capítulo.
- `Domain/Reader.swift`: `ChapterBuilder` devuelve bloques (`[Block]`) en lugar de `[DisplayVerse]`. Cada bloque es un título, un párrafo, una línea de poesía o una línea en blanco, con su lista de trozos `(verse, text)`. Hay que respetar la lógica que ya existe para versículos fusionados (CUV Núm 1:20 = 20–21) y para títulos que caen en versículos que faltan.
- `UI/Reader/ReaderView.swift`:
  - Prosa como texto corrido (`Text` concatenado o `AttributedString`) con el número en superíndice y en color atenuado.
  - Poesía con la sangría de su nivel, más una sangría francesa para las líneas que no caben.
  - Títulos con estilos distintos según `ms`, `s1`, `s2`, `d` y `r`.
  - Seleccionar, resaltar y saltar a un versículo (`ChapterPosition`) tiene que seguir funcionando por versículo, aunque esté dentro de un párrafo.
- `UI/Settings/SettingsView.swift`: un ajuste "Diseño: Párrafos / Un versículo por línea". El segundo modo es el comportamiento de ahora.

### 4. Verificación

- Ampliar `data/test_bundle.py` con estos casos:
  - Sal 23 en CUV, KJV y ASV tiene líneas `q`.
  - Gén 1 en KJV abre párrafos donde hay `¶`.
  - Jn 3 tiene más de un párrafo en todas las versiones, RV1909 incluida.
  - Por cada versículo, la concatenación de sus trozos coincide con `verses.text`.
  - Ningún capítulo de RV1909 tiene un único bloque, salvo los de un solo versículo.
- Ampliar los tests de Swift (`App/Tests`) con `ChapterBuilder` sobre datos sintéticos: un versículo partido entre prosa y poesía, un versículo fusionado y un título en un versículo ausente.
- `swift build` y `swift test` en verde. Arrancar la app y revisar a ojo Gén 1, Sal 23, Is 40, Mt 5 y Rom 8 en las cuatro versiones.

### Fuera de alcance (anotar, no hacer)

- Usar los Strong del USFM de RV1909 para dar léxico también en español.
- Las "palabras de Jesús en rojo" (`wordsOfJesus`) ya vienen en los datos, pero no hay que implementarlas ahora.

Fuentes: USFM (ubsicap.github.io/usfm), esquema de HelloAO (bible-api.pages.dev/docs/reference) y eBible.org (spaRV1909, engbsb).
