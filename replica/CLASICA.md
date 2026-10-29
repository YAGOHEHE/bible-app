# Biblia Clásica — versión para macOS 10.13+ (Intel y Apple Silicon)

## Decisiones del usuario (2026-10-29)
- macOS mínimo **10.13 High Sierra**; **todas las funciones de la 1.1**; **dos apps**: «Biblia» (actual, macOS 14+)
  y «Biblia Clásica» (esta), cada una con su DMG, compartiendo datos y lógica.

## Restricciones técnicas
- Mac con macOS 10.x = Intel → binario **universal (x86_64 + arm64)** o al menos x86_64; deployment target 10.13.
- macOS < 10.14.4 no trae el runtime de Swift → **incrustar** las librerías de
  `/Library/Developer/CommandLineTools/usr/lib/swift-5.0/macosx/` en `Contents/Frameworks` (rpath
  `@executable_path/../Frameworks`). Concurrency (`async/await`, `Task`, `@MainActor`) solo existe desde 10.15 →
  **prohibido en el código compartido y en la app clásica** (usar GCD / callbacks).
- SwiftUI no existe en 10.13/10.14 → **interfaz en AppKit**: `NSSplitViewController`, `NSOutlineView` (libros),
  `NSTextView` + `NSAttributedString` (lector: párrafos, poesía, títulos, superíndices, enlaces, resaltados,
  selección), `NSPopover`/barra inferior para acciones, `NSWindow` de ajustes, menús con atajos.
- Este Mac (M1 Pro) **no puede ejecutar macOS 10.x** (ni en VM). Verificación local = compilar, comprobar
  `vtool -show-build` (minos 10.13), `otool -L`/`-l` (sin dependencias de APIs > 10.13), `lipo -info`, tests del
  núcleo y ejecutar la app clásica en este Mac (macOS 14) como prueba funcional. **Prueba real: en un Mac del grupo.**
- Sin Xcode: solo Command Line Tools (`swift build --triple x86_64-apple-macosx10.13` + `--triple arm64-apple-macosx11`
  y `lipo`). Tests: `import Testing` (corren en este Mac).

## Arquitectura
`App/Package.swift` pasa a tener:
- `BibliaCore` (library): `Domain/` + `Data/` actuales, compilable con deployment 10.13 (sin concurrency; APIs
  nuevas detrás de `#available` con alternativa: `NoteEditing.swift`, `ReferenceParser.swift`, `DateText` …).
- `BibliaApp` (ejecutable SwiftUI, macOS 14) — depende de `BibliaCore`; **sin cambios de comportamiento**.
- `BibliaClassic` (ejecutable AppKit, macOS 10.13) — depende de `BibliaCore`.
- Tests: los actuales + `BibliaCoreTests`.
Datos de usuario de la clásica en `~/Library/Application Support/Biblia Clásica/user.sqlite`;
bundle id `org.biblia.clasica`; mismo `bible.sqlite`.

## Oleadas (subagentes Sonnet, secuenciales; rama `clasica` en `~/Projects/biblia-app-clasica`)
- **L0 Viabilidad**: separar `BibliaCore`; que compile para `x86_64-apple-macosx10.13` y `arm64-apple-macosx11`;
  esqueleto AppKit que abre una ventana con Juan 3 desde `bible.sqlite`; `scripts/make_classic_app.sh`
  (universal + runtime incrustado + firma ad-hoc); verificación con vtool/otool/lipo; la app moderna y sus 124 tests
  siguen en verde.
- **L1 Lector**: barra lateral libros/capítulos/recientes, lector NSTextView (párrafos, poesía, títulos, versículos
  fusionados), temas claro/oscuro/sepia (oscuro solo 10.14+), tamaño de letra, retomar, ←/→, ir a (⌘L), ajustes.
- **L2 Paralela**: columnas limpias y «principal + glosas» con selector por idioma; gestor de versiones.
- **L3 Estudio**: búsqueda (⌘F), Strong + inspector, historial, referencias cruzadas.
- **L4 Anotaciones**: clic → barra de acciones, resaltados, marcadores, notas Markdown, panel Notas, menú contextual.
- **L5 Entrega**: `Biblia-Clasica-1.1.0.dmg`, guía `INSTALAR-CLASICA.md` (10.13: clic derecho → Abrir),
  checklist de prueba para un Mac antiguo real, merge de `BibliaCore` a `main`.
