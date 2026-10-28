# Brief de icono de app (marca provisional "BibliaApp")

Objetivo: icono original para macOS (1024×1024, cuadrado redondeado con la plantilla de Big Sur+, sombra suave del sistema). Nada de cruz, libro abierto clásico, paloma, ni nada que imite el icono del producto de referencia (no consultado). Debe reconocerse a 16 px y verse bien sobre dock claro y oscuro.

Paleta de marca provisional (coherente con `tokens.json`): índigo tinta `#3447A0`, sepia cálido `#F4ECD8`, acento ámbar `#946B00`/`#D9B24A` para un único punto de luz. Un solo plano de color más una forma; sin degradados complicados (un degradado suave índigo claro -> oscuro de arriba abajo).

## Concepto A: "Dos voces, un texto"
Dos formas de columna verticales (rectángulos de esquinas redondeadas) lado a lado, una índigo oscuro y otra sepia clara, que se solapan en el centro formando una tercera zona ámbar; alude a comparar versiones en paralelo. Sobre la zona ámbar, un pequeño punto (la palabra con Strong). Sin texto. Variante pequeña (16-32 px): solo las dos columnas y el punto.

## Concepto B: "Luz en el margen"
Una página sepia vista de frente con un gran número de versículo en superíndice (el glifo "1" en serif, índigo) que nace en la esquina superior izquierda, y debajo tres líneas de texto onduladas, la central con un subrayado punteado ámbar (el motivo del Strong). Evoca estudio y lectura detallada sin libro ni cruz. Variante pequeña: solo el "1" y el punto ámbar.

## Entregables y reglas
- Fuente: SVG propio o Icon Composer (`.icon`), sin fuentes con licencia (usar glifo dibujado para el "1").
- Export: 1024 con margen de seguridad del 10 %; los tamaños 16-512 salen de `AppIcon.appiconset`.
- Prueba: sobre fondo claro, oscuro y mosaico del Dock; contraste forma/fondo >= 3:1.
- Sustituible tras el naming final; el nombre del activo es `AppIcon`.
