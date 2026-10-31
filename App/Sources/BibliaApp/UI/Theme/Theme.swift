import BibliaCore
import SwiftUI
import AppKit

enum ThemeChoice: String, CaseIterable, Codable, Identifiable {
    case system, light, dark, sepia
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: "Sistema"
        case .light: "Claro"
        case .dark: "Oscuro"
        case .sepia: "Sepia"
        }
    }
}

extension Color {
    static func hex(_ v: UInt32) -> Color {
        Color(.sRGB, red: Double((v >> 16) & 0xFF) / 255,
              green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
}

/// Valores copiados de `replica/design/tokens.json` (único sitio con colores literales).
struct ThemePalette {
    let background, surface, textPrimary, textSecondary, textMuted: Color
    let accent, onAccent, verseNumber, heading, strongUnderline: Color
    let searchHighlight, selection, border, borderInput, focusRing, danger: Color
    /// Color de acento por versión (solo como color de texto: sigla/cabecera; contraste >= 4,5:1 sobre `background`).
    let versionAccent: [Color]
    /// Fondos de resaltado (bajo el texto) y su mezcla con `selection` cuando el versículo está seleccionado.
    let highlight: [HighlightColor: Color]
    let highlightSelected: [HighlightColor: Color]
    let bookmarkMarker: Color

    /// `y,g,b,p,o` = amarillo, verde, azul, rosa, naranja (orden de `HighlightColor.allCases`).
    private static func highlights(_ hex: [UInt32], selection: UInt32)
        -> ([HighlightColor: Color], [HighlightColor: Color]) {
        var a: [HighlightColor: Color] = [:], b: [HighlightColor: Color] = [:]
        for (c, h) in zip(HighlightColor.allCases, hex) {
            a[c] = .hex(h); b[c] = .hex(mix(h, selection))
        }
        return (a, b)
    }
    static func mix(_ a: UInt32, _ b: UInt32) -> UInt32 {
        func ch(_ s: Int) -> UInt32 { ((((a >> s) & 0xFF) + ((b >> s) & 0xFF)) / 2) << s }
        return ch(16) | ch(8) | ch(0)
    }

    static let light = ThemePalette(
        background: .hex(0xFBFAF7), surface: .hex(0xF2F0EA),
        textPrimary: .hex(0x1C1A17), textSecondary: .hex(0x57534B), textMuted: .hex(0x6E6960),
        accent: .hex(0x9E2B1F), onAccent: .hex(0xFFFFFF), verseNumber: .hex(0x9E2B1F),
        heading: .hex(0x1C1A17), strongUnderline: .hex(0xB3A27E),
        searchHighlight: .hex(0xF7E08A), selection: .hex(0xF2DFD6),
        border: .hex(0xE4E0D6), borderInput: .hex(0x8A857B), focusRing: .hex(0x9E2B1F),
        danger: .hex(0xB3261E),
        versionAccent: [.hex(0x9E2B1F), .hex(0x2F5F8A), .hex(0x3F6B3A)],
        highlight: highlights([0xF7E9A8, 0xDCEBCF, 0xD3E4F0, 0xF4D9DE, 0xF1DCC6], selection: 0xF2DFD6).0,
        highlightSelected: highlights([0xF7E9A8, 0xDCEBCF, 0xD3E4F0, 0xF4D9DE, 0xF1DCC6], selection: 0xF2DFD6).1,
        bookmarkMarker: .hex(0xC2412D))

    static let dark = ThemePalette(
        background: .hex(0x16181B), surface: .hex(0x1E2125),
        textPrimary: .hex(0xE9E5DB), textSecondary: .hex(0xB7B1A5), textMuted: .hex(0x8F897E),
        accent: .hex(0xEE8B76), onAccent: .hex(0x2A0F09), verseNumber: .hex(0xEE8B76),
        heading: .hex(0xE9E5DB), strongUnderline: .hex(0x7D7464),
        searchHighlight: .hex(0x6A5A1A), selection: .hex(0x3A2621),
        border: .hex(0x2E3237), borderInput: .hex(0x6F6A61), focusRing: .hex(0xEE8B76),
        danger: .hex(0xFF8F86),
        versionAccent: [.hex(0xEE8B76), .hex(0x8FB8E0), .hex(0x9BCB98)],
        highlight: highlights([0x4A4220, 0x2A4128, 0x233B4C, 0x4A2932, 0x4B3420], selection: 0x3A2621).0,
        highlightSelected: highlights([0x4A4220, 0x2A4128, 0x233B4C, 0x4A2932, 0x4B3420], selection: 0x3A2621).1,
        bookmarkMarker: .hex(0xF08A6E))

    static let sepia = ThemePalette(
        background: .hex(0xF4EDDD), surface: .hex(0xECE3CE),
        textPrimary: .hex(0x33291D), textSecondary: .hex(0x54452F), textMuted: .hex(0x6B5A44),
        accent: .hex(0x8A2E17), onAccent: .hex(0xFFF8EC), verseNumber: .hex(0x8A2E17),
        heading: .hex(0x33291D), strongUnderline: .hex(0xB9A47C),
        searchHighlight: .hex(0xEFCB62), selection: .hex(0xE6D3AE),
        border: .hex(0xD9CDB1), borderInput: .hex(0x85704F), focusRing: .hex(0x8A2E17),
        danger: .hex(0xA3271B),
        versionAccent: [.hex(0x8A2E17), .hex(0x2F5A7A), .hex(0x3F6B3A)],
        highlight: highlights([0xF0E1A8, 0xD4E0B0, 0xC3D9D6, 0xECCFC8, 0xEDCB9E], selection: 0xE6D3AE).0,
        highlightSelected: highlights([0xF0E1A8, 0xD4E0B0, 0xC3D9D6, 0xECCFC8, 0xEDCB9E], selection: 0xE6D3AE).1,
        bookmarkMarker: .hex(0xA3401C))
}

struct Theme {
    let palette: ThemePalette
    let fontScale: Double
    let isSepia: Bool

    /// Tamaño de lectura base (pt) al 100 %; `fontScale` lo multiplica.
    static let baseSize: CGFloat = 19
    /// Ancho máximo de la columna de texto del lector (pt).
    static let readingColumnWidth: CGFloat = 640
    /// Interlineado (múltiplo del tamaño): latino / chino.
    static let lineMultipleLatin: CGFloat = 1.72
    static let lineMultipleCJK: CGFloat = 1.9

    // MARK: fuentes de lectura (Literata + Songti SC; .serif del sistema si Literata no se registró)

    enum ReadingWeight { case regular, medium, semibold }

    /// Fuente AppKit de lectura: única fuente de verdad para SwiftUI (`readingFont`) y para medir/dibujar fondos redondeados.
    static func readingNSFont(latin: Bool, size: CGFloat, weight: ReadingWeight = .regular, italic: Bool = false) -> NSFont {
        if latin {
            if FontRegistry.literataAvailable {
                let weightName: String = switch weight {
                case .regular: "Literata-Regular"
                case .medium: "Literata-Medium"
                case .semibold: "Literata-SemiBold"
                }
                let name = italic ? "Literata-Italic" : weightName
                if let f = NSFont(name: name, size: size) { return f }
            }
            let w: NSFont.Weight = switch weight { case .regular: .regular; case .medium: .medium; case .semibold: .semibold }
            let base = NSFont.systemFont(ofSize: size, weight: w)
            var d = base.fontDescriptor.withDesign(.serif) ?? base.fontDescriptor
            if italic { d = d.withSymbolicTraits(.italic) }
            return NSFont(descriptor: d, size: size) ?? base
        }
        return NSFont(name: "Songti SC", size: size) ?? NSFont.systemFont(ofSize: size)
    }

    func readingNSFont(latin: Bool, size: CGFloat? = nil, weight: ReadingWeight = .regular, italic: Bool = false) -> NSFont {
        Theme.readingNSFont(latin: latin, size: (size ?? Theme.baseSize) * fontScale, weight: weight, italic: italic)
    }

    /// Fuente de lectura (`size` es el tamaño al 100 %; se multiplica por `fontScale`).
    func readingFont(latin: Bool, size: CGFloat = Theme.baseSize, weight: ReadingWeight = .regular, italic: Bool = false) -> Font {
        Font(readingNSFont(latin: latin, size: size, weight: weight, italic: italic) as CTFont)
    }
    /// Serif latina (Literata) a un tamaño ABSOLUTO en pt (títulos y cabeceras ya escalados).
    func serifFont(size: CGFloat, weight: ReadingWeight = .regular, italic: Bool = false) -> Font {
        Font(Theme.readingNSFont(latin: true, size: size, weight: weight, italic: italic) as CTFont)
    }
    /// Fuente de interfaz: SF del sistema (no escala con el lector).
    func uiFont(size: CGFloat, weight: Font.Weight = .regular) -> Font { .system(size: size, weight: weight) }

    /// Interlineado extra (SwiftUI/AppKit lo suman a la altura natural de la fuente) para lograr 1,72 / 1,9.
    func lineSpacing(latin: Bool, size: CGFloat? = nil) -> CGFloat {
        let s = (size ?? Theme.baseSize) * fontScale
        let natural = Theme.naturalLineHeight(readingNSFont(latin: latin, size: size))
        return max(0, s * (latin ? Theme.lineMultipleLatin : Theme.lineMultipleCJK) - natural)
    }
    static func naturalLineHeight(_ f: NSFont) -> CGFloat { ceil(f.ascender - f.descender + f.leading) }

    var pt: CGFloat { Theme.baseSize * fontScale }

    // MARK: número de versículo y cabeceras

    /// SF semibold a 0,58 del tamaño de lectura.
    var verseNumberFont: Font { .system(size: pt * 0.58, weight: .semibold).monospacedDigit() }
    var verseNumberNSFont: NSFont { NSFont.monospacedDigitSystemFont(ofSize: pt * 0.58, weight: .semibold) }
    var verseNumberBaseline: CGFloat { pt * 0.40 }

    var headingFont: Font { serifFont(size: pt * 0.92, weight: .semibold) }
    /// Cabecera de capítulo: nombre del libro en mayúsculas pequeñas (SF semibold 12, espaciado 0,16 em)…
    var chapterBookFont: Font { .system(size: 12, weight: .semibold) }
    static let chapterBookTracking: CGFloat = 12 * 0.16
    /// … y número de capítulo grande (Literata Medium, 3,8 × tamaño de lectura, color acento).
    var chapterNumberFont: Font { serifFont(size: pt * 3.8, weight: .medium) }
    /// Título de capítulo en una línea (vista paralela, hasta que se rediseñe): serif de 1,6 × lectura.
    var chapterTitleFont: Font { serifFont(size: pt * 1.6, weight: .semibold) }
    var verseGap: CGFloat { pt * 0.35 }
    var paragraphGap: CGFloat { pt * 0.9 }
}

private struct ThemeKey: EnvironmentKey {
    static let defaultValue = Theme(palette: .light, fontScale: 1, isSepia: false)
}
extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

/// Aplicar UNA vez en la raíz de cada ventana (lector y Ajustes).
struct ThemedRoot: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    var settings: AppSettings

    func body(content: Content) -> some View {
        let palette: ThemePalette = switch settings.themeChoice {
        case .light: .light
        case .dark: .dark
        case .sepia: .sepia
        case .system: scheme == .dark ? .dark : .light
        }
        content
            .environment(\.theme, Theme(palette: palette, fontScale: settings.fontScale,
                                        isSepia: settings.themeChoice == .sepia))
            .preferredColorScheme(settings.themeChoice == .sepia ? .light :
                                    settings.themeChoice == .light ? .light :
                                    settings.themeChoice == .dark ? .dark : nil)
    }
}

extension View {
    func themedRoot(_ settings: AppSettings) -> some View { modifier(ThemedRoot(settings: settings)) }
}
