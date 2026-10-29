# Brief de icono de app (marca provisional "BibliaApp")

## Concepto final: cruz latina (decisión del usuario, v1.1)
Una cruz latina sencilla, crema (`#F4ECD8`, con degradado muy sutil `#FFF9EA` -> `#EADFC0`), centrada sobre el fondo "squircle" índigo actual (degradado `#4A5DB8` arriba -> `#2C3470` abajo, coherente con `tokens.json`). Sin brillos, rayos ni libro. Sombra suave bajo la cruz (desplazamiento 8 px, desenfoque 16 px, 45 %) y la sombra de sistema del squircle.

Razón: reconocible al instante incluso a 16 px (dos barras de alto contraste crema/índigo, ~9:1), tono sobrio acorde con una app de lectura, y mantiene la identidad cromática anterior.

### Medidas (lienzo 1024, cuerpo 824 px, margen 100 px)
- Altura total de la cruz: 520 px (63 % del cuerpo). Ancho de los brazos: 372 px (brazos iguales de 128 px a cada lado del eje).
- Grosor de barras: 116 px (14,1 % del cuerpo); esquinas con radio ~4 px.
- Travesaño: su centro a 1/3 de la altura desde arriba (travesaño de y=top-173 ± 58); el palo inferior mide ~347 px frente a ~173 px superior (proporción latina).
- Centrado óptico: la caja de la cruz queda 14 px por encima del centro geométrico (eje vertical x=512).
- Prueba a 16/32 px: legible y equilibrada; a 16 px el travesaño ocupa ~2 px y la cruz se lee sin ambigüedad.

### Generación
`scripts/make_icon.sh` -> `scripts/make_icon.swift` (CoreGraphics) -> `App/Icon/Biblia-1024.png` -> iconset temporal (16-512 @1x/@2x con `sips`) -> `App/Icon/Biblia.icns` (`iconutil`). Previsualizaciones: `replica/screens/icon-cross-{1024,32,16}.png`.

## Reglas
- Prueba sobre dock claro y oscuro; contraste forma/fondo >= 3:1 (cumplido).
- Sustituible tras el naming final.

## Conceptos descartados (v1.0)
A "Dos voces, un texto" (columnas solapadas con punto ámbar, icono de 1.0.0) y B "Luz en el margen" (página con versículo en superíndice).
