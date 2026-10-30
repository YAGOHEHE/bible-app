# Brief de icono de app (marca provisional "BibliaApp")

## Concepto final: «Códice» (decisión del usuario, v1.2)
Libro abierto crema sobre squircle color tinta (degradado `#2C3C46` arriba -> `#131B21` abajo). La cruz latina no se dibuja: es el hueco entre las páginas (pliegue vertical de 56 px) más un travesaño calado de 280 × 56 px con su centro a ~1/3 de la altura. Una cinta de marcapáginas roja (`#D8543B` -> `#B23A24`, cola en V) cae del lomo. Coherente con el sistema visual «Códice» (rojo rúbrica como único acento).

Razón: mantiene la cruz elegida en la v1.1 pero la integra en un libro, de modo que comunica «lectura bíblica» y no un símbolo genérico; la cinta alude a marcadores y notas. A 16 px se leen el libro y la cruz (contraste crema/tinta ~13:1).

### Medidas (lienzo 1024, cuerpo 824 px, margen 100 px; origen arriba a la izquierda)
- Página izquierda: de x=236 a x=484; borde superior curvo (y 300 en el canto, 318 en el pliegue), inferior de 728 a 746. La derecha es simétrica (540-788).
- Colores de página: izquierda `#EFE7D6`, derecha `#FBF6EA`, con un sombreado del 18 % hacia el pliegue; sombra bajo las páginas (10 px, desenfoque 22 px, 45 %).
- Travesaño: x 372-652, y 430-486, relleno con el mismo degradado del fondo (en coordenadas absolutas), así el calado es exacto.
- Cinta: x 496-528, y 690-866, muesca en V de 16 px.

### Generación
`scripts/make_icon.sh` -> `scripts/make_icon.swift` (CoreGraphics) -> `App/Icon/Biblia-1024.png` -> iconset temporal (16-512 @1x/@2x con `sips`) -> `App/Icon/Biblia.icns` (`iconutil`). Previsualizaciones: `replica/screens/icon-codice-{1024,32,16,dock}.png`.

## Reglas
- Prueba sobre dock claro y oscuro; contraste forma/fondo >= 3:1 (cumplido).
- Sustituible tras el naming final.

## Conceptos descartados
v1.2: B «Cinta» (marcapáginas rojo con cruz calada sobre papel) y C «Página» (libro sin símbolo sobre rojo).
v1.1: cruz latina crema sobre squircle índigo (`replica/screens/icon-cross-*.png`).
v1.0: A "Dos voces, un texto" y B "Luz en el margen".
