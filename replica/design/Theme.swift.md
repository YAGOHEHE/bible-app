# Theme.swift: guía de implementación

Fuente de verdad: `replica/design/tokens.json`. Decisión: **colores calculados desde constantes Swift generadas/copiadas de los tokens, no Asset Catalog** (hay tres temas, uno de ellos "sepia" que no es una apariencia del sistema; los Color assets solo cubren light/dark). Un único tipo `Theme` inyectado por `Environment`. Si cambian los tokens, se actualiza solo `ThemePalette`.

```swift
import SwiftUI

enum ThemeChoice: String, CaseIterable, Codable { case system, light, dark, sepia }

struct ThemePalette {
    let background, surface, textPrimary, textSecondary, textMuted: Color
    let accent, onAccent, verseNumber, heading, strongUnderline: Color
    let searchHighlight, selection, border, borderInput, focusRing, danger: Color
    let versionAccent: [Color]       // [v1, v2, v3] solo color de texto

    static let light = ThemePalette(
        background: .hex(0xFFFFFF), surface: .hex(0xF5F5F7),
        textPrimary: .hex(0x1D1D1F), textSecondary: .hex(0x48484F), textMuted: .hex(0x66666E),
        accent: .hex(0x3447A0), onAccent: .hex(0xFFFFFF), verseNumber: .hex(0x6A5A8E),
        heading: .hex(0x2C3470), strongUnderline: .hex(0x946B00),
        searchHighlight: .hex(0xFFE17A), selection: .hex(0xC9DAFF),
        border: .hex(0xD8D8DE), borderInput: .hex(0x85858F), focusRing: .hex(0x3447A0),
        danger: .hex(0xB3261E),
        versionAccent: [.hex(0x3447A0), .hex(0x1F6B45), .hex(0x9A4B00)])
    static let dark = ThemePalette( /* valores de tokens.color.dark */ )
    static let sepia = ThemePalette( /* valores de tokens.color.sepia */ )
}

extension Color {
    static func hex(_ v: UInt32) -> Color {
        Color(.sRGB, red: Double((v >> 16) & 0xFF) / 255,
              green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
}

@Observable final class ThemeSettings {          // persistido en la BD de usuario (Settings)
    var choice: ThemeChoice = .system
    var fontScale: Double = 1.0                  // 0.8...2.0, paso 0.1
}

struct Theme {
    let palette: ThemePalette
    let fontScale: Double
    let isSepia: Bool

    func readingFont(latin: Bool, size: CGFloat = 17) -> Font {
        let s = size * fontScale
        return latin ? .system(size: s, design: .serif)   // New York
                     : .custom("Songti SC", size: s)      // fallback: PingFang SC
    }
    var lineSpacingLatin: CGFloat { 17 * fontScale * (1.55 - 1.2) }  // aprox. al lineHeight 1.55
    var lineSpacingCJK:   CGFloat { 17 * fontScale * (1.85 - 1.2) }
    var verseNumberFont: Font { .system(size: 17 * 0.62 * fontScale, weight: .semibold).monospacedDigit() }
    // Superíndice: en AttributedString usar .baselineOffset = 17*0.38*fontScale
}

private struct ThemeKey: EnvironmentKey {
    static let defaultValue = Theme(palette: .light, fontScale: 1, isSepia: false)
}
extension EnvironmentValues { var theme: Theme { get { self[ThemeKey.self] } set { self[ThemeKey.self] = newValue } } }

/// Aplicar UNA vez en la raíz de la ventana y de cada ventana auxiliar (Settings incluida).
struct ThemedRoot<Content: View>: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    var settings: ThemeSettings
    func body(content: Content) -> some View {
        let palette: ThemePalette = switch settings.choice {
            case .light: .light
            case .dark:  .dark
            case .sepia: .sepia
            case .system: scheme == .dark ? .dark : .light
        }
        content
            .environment(\.theme, Theme(palette: palette, fontScale: settings.fontScale,
                                        isSepia: settings.choice == .sepia))
            // Sepia es una apariencia clara: forzar light para controles nativos del lector
            .preferredColorScheme(settings.choice == .sepia ? .light :
                                  settings.choice == .light ? .light :
                                  settings.choice == .dark ? .dark : nil)
    }
}
```

## Reglas para los builders

1. **Nunca** escribir colores literales ni `Color.primary` en vistas de lectura; usar `@Environment(\.theme) var theme` y `theme.palette.*`. Excepción: controles del sistema (Slider, Toggle, listas de Ajustes) conservan el estilo nativo.
2. `ThemeChoice.system` sigue `@Environment(\.colorScheme)`; al cambiar la apariencia del sistema, `ThemedRoot` se recalcula solo (verificar F07).
3. **Sepia** solo cambia el lector, columnas y inspector. El cromo (toolbar, barra lateral) usa la apariencia del sistema; `.preferredColorScheme(.light)` evita controles oscuros sobre papel. Documentar en Ajustes: "Papel".
4. Fuentes: `readingFont(latin:)` por run. Construir el `AttributedString` por versículo con atributo `Locale.Language` y dos fuentes (Latin y CJK); la cascada de macOS pone los glifos CJK en Songti SC. Verificar con una cadena mixta ("Dios 神 amó 爱") que el interlineado no salta.
5. Tamaños: todo el lector multiplica por `theme.fontScale`; **no** usar `.dynamicTypeSize` en el lector. Al cambiar `fontScale` conservar el versículo ancla (`ScrollViewReader`, `scrollTo(anchor: .top)`).
6. Subrayado Strong: `AttributedString` con `underlineStyle = .init(pattern: .dot, styleType: .single)` y `underlineColor = strongUnderline`, solo si modo Strong; hover con `onHover` + cambio a `.single`.
7. Búsqueda: aplicar `backgroundColor = searchHighlight` y `foregroundColor = textPrimary` en el rango.
8. Paralela: `theme.palette.versionAccent[index % 3]` como color de texto de la sigla de la versión (sin fondos).
9. Animaciones: usar `withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2))` con `@Environment(\.accessibilityReduceMotion)`.
10. Tras cualquier cambio de paleta, correr `python3 contrast.py replica/design/tokens.json`; debe salir con código 0.
