import AppKit
import BibliaCore

/// Colores de un tema de lectura «Códice» (valores de replica/design/tokens.json, idénticos a `ThemePalette` de la app SwiftUI).
public struct ReaderPalette {
    public let isDark: Bool
    public let background, surface, textPrimary, textSecondary, textMuted: NSColor
    public let accent, onAccent, verseNumber, heading, selection, border, borderInput, focusRing, danger: NSColor
    /// Subrayado punteado de las palabras Strong (token `strong-underline`).
    public let strongUnderline: NSColor
    /// Fondo de las coincidencias de búsqueda (token `search-highlight`).
    public let searchHighlight: NSColor
    /// Acentos de texto de las versiones 1-3 (tokens `version-1..3`); las columnas 4+ repiten.
    public let version: [NSColor]
    /// Fondos de resaltado (tokens `highlight-*`) y marcador (`bookmark-marker`).
    public let highlights: [HighlightColor: NSColor]
    public let bookmarkMarker: NSColor
    public func highlight(_ c: HighlightColor) -> NSColor { highlights[c] ?? selection }
    public func versionColor(_ i: Int) -> NSColor { version[((i % 3) + 3) % 3] }

    public static func hex(_ v: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }

    /// `y,g,b,p,o` = amarillo, verde, azul, rosa, naranja (orden de `HighlightColor.allCases`).
    private static func hl(_ h: [UInt32]) -> [HighlightColor: NSColor] {
        var d: [HighlightColor: NSColor] = [:]
        for (c, v) in zip(HighlightColor.allCases, h) { d[c] = hex(v) }
        return d
    }

    public static let light = ReaderPalette(
        isDark: false, background: hex(0xFBFAF7), surface: hex(0xF2F0EA), textPrimary: hex(0x1C1A17),
        textSecondary: hex(0x57534B), textMuted: hex(0x6E6960), accent: hex(0x9E2B1F), onAccent: hex(0xFFFFFF),
        verseNumber: hex(0x9E2B1F), heading: hex(0x1C1A17), selection: hex(0xF2DFD6), border: hex(0xE4E0D6),
        borderInput: hex(0x8A857B), focusRing: hex(0x9E2B1F), danger: hex(0xB3261E),
        strongUnderline: hex(0xB3A27E), searchHighlight: hex(0xF7E08A),
        version: [hex(0x9E2B1F), hex(0x2F5F8A), hex(0x3F6B3A)],
        highlights: hl([0xF7E9A8, 0xDCEBCF, 0xD3E4F0, 0xF4D9DE, 0xF1DCC6]),
        bookmarkMarker: hex(0xC2412D))
    public static let dark = ReaderPalette(
        isDark: true, background: hex(0x16181B), surface: hex(0x1E2125), textPrimary: hex(0xE9E5DB),
        textSecondary: hex(0xB7B1A5), textMuted: hex(0x8F897E), accent: hex(0xEE8B76), onAccent: hex(0x2A0F09),
        verseNumber: hex(0xEE8B76), heading: hex(0xE9E5DB), selection: hex(0x3A2621), border: hex(0x2E3237),
        borderInput: hex(0x6F6A61), focusRing: hex(0xEE8B76), danger: hex(0xFF8F86),
        strongUnderline: hex(0x7D7464), searchHighlight: hex(0x6A5A1A),
        version: [hex(0xEE8B76), hex(0x8FB8E0), hex(0x9BCB98)],
        highlights: hl([0x4A4220, 0x2A4128, 0x233B4C, 0x4A2932, 0x4B3420]),
        bookmarkMarker: hex(0xF08A6E))
    public static let sepia = ReaderPalette(
        isDark: false, background: hex(0xF4EDDD), surface: hex(0xECE3CE), textPrimary: hex(0x33291D),
        textSecondary: hex(0x54452F), textMuted: hex(0x6B5A44), accent: hex(0x8A2E17), onAccent: hex(0xFFF8EC),
        verseNumber: hex(0x8A2E17), heading: hex(0x33291D), selection: hex(0xE6D3AE), border: hex(0xD9CDB1),
        borderInput: hex(0x85704F), focusRing: hex(0x8A2E17), danger: hex(0xA3271B),
        strongUnderline: hex(0xB9A47C), searchHighlight: hex(0xEFCB62),
        version: [hex(0x8A2E17), hex(0x2F5A7A), hex(0x3F6B3A)],
        highlights: hl([0xF0E1A8, 0xD4E0B0, 0xC3D9D6, 0xECCFC8, 0xEDCB9E]),
        bookmarkMarker: hex(0xA3401C))

    /// Paleta efectiva: «Sistema» sigue la apariencia de la app (oscuro solo en 10.14+).
    public static func resolve(_ choice: ThemeChoice) -> ReaderPalette {
        switch choice {
        case .light: return light
        case .dark: return dark
        case .sepia: return sepia
        case .system:
            if #available(macOS 10.14, *) {
                let name = NSApp?.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua])
                return name == .darkAqua ? dark : light
            }
            return light
        }
    }
}

/// Fuentes de lectura «Códice»: Literata (latín; registrada al arrancar con `FontRegistry`), Songti SC (chino).
public enum ReaderFonts {
    public enum Weight { case regular, medium, semibold }

    /// Tamaño de lectura al 100 % (pt), ancho máximo de la columna (pt) e interlineado (múltiplo del tamaño).
    public static let baseSize: CGFloat = 19
    public static let columnWidth: CGFloat = 640
    public static let lineMultipleLatin: CGFloat = 1.72
    public static let lineMultipleCJK: CGFloat = 1.9

    /// Serif latina: Literata si se registró; si no, New York (10.15+) o Iowan Old Style / Georgia / Times New Roman.
    public static func latin(size: CGFloat, weight: Weight = .regular, italic: Bool = false) -> NSFont {
        if FontRegistry.literataAvailable {
            let name: String
            if italic { name = "Literata-Italic" }
            else { name = weight == .regular ? "Literata-Regular" : (weight == .medium ? "Literata-Medium" : "Literata-SemiBold") }
            if let f = NSFont(name: name, size: size) { return f }
        }
        var base: NSFont?
        if #available(macOS 10.15, *) {
            let w: NSFont.Weight = weight == .regular ? .regular : (weight == .medium ? .medium : .semibold)
            let sys = NSFont.systemFont(ofSize: size, weight: w)
            if let d = sys.fontDescriptor.withDesign(.serif), let f = NSFont(descriptor: d, size: size) { base = f }
        }
        if base == nil {
            for n in ["Iowan Old Style", "Georgia", "Times New Roman"] {
                if let f = NSFont(name: n, size: size) { base = f; break }
            }
        }
        var out = base ?? NSFont.systemFont(ofSize: size)
        if weight == .semibold, !isNewYorkSystem(out) { out = NSFontManager.shared.convert(out, toHaveTrait: .boldFontMask) }
        if italic { out = NSFontManager.shared.convert(out, toHaveTrait: .italicFontMask) }
        return out
    }
    private static func isNewYorkSystem(_ f: NSFont) -> Bool { f.familyName == "New York" }

    /// Chino: Songti SC (宋体); alternativas PingFang SC, STSong, Hiragino Sans GB.
    public static func cjk(size: CGFloat) -> NSFont {
        for n in ["Songti SC", "STSong", "PingFang SC", "Hiragino Sans GB"] {
            if let f = NSFont(name: n, size: size) { return f }
        }
        return NSFont.systemFont(ofSize: size)
    }

    public static func reading(latin isLatin: Bool, size: CGFloat) -> NSFont { isLatin ? latin(size: size) : cjk(size: size) }

    public static func traits(_ f: NSFont, bold: Bool = false, italic: Bool = false) -> NSFont {
        if f.familyName == "Literata" {      // sin negrita real: semibold / cursiva propias
            return latin(size: f.pointSize, weight: bold ? .semibold : .regular, italic: italic)
        }
        var out = f
        if bold { out = NSFontManager.shared.convert(out, toHaveTrait: .boldFontMask) }
        if italic { out = NSFontManager.shared.convert(out, toHaveTrait: .italicFontMask) }
        return out
    }

    public static func naturalLineHeight(_ f: NSFont) -> CGFloat { ceil(f.ascender - f.descender + f.leading) }

    /// Interlineado extra (AppKit lo suma a la altura natural de la fuente) para lograr 1,72 (latín) / 1,9 (chino).
    public static func lineSpacing(latin isLatin: Bool, size: CGFloat) -> CGFloat {
        max(0, size * (isLatin ? lineMultipleLatin : lineMultipleCJK) - naturalLineHeight(reading(latin: isLatin, size: size)))
    }

    /// Número de versículo: SF semibold (dígitos tabulares) a 0,58 del tamaño de lectura; el llamador lo sube como superíndice.
    public static func verseNumber(size: CGFloat) -> NSFont {
        NSFont.monospacedDigitSystemFont(ofSize: size, weight: .semibold)
    }
    public static func verseNumberSize(forReading pt: CGFloat) -> CGFloat { pt * 0.58 }
    public static func verseNumberBaseline(forReading pt: CGFloat) -> CGFloat { pt * 0.40 }

    /// Cabecera de capítulo: nombre del libro (SF semibold 12, espaciado 0,16 em) y número grande (Literata Medium 3,8 × lectura).
    public static let chapterBookFont = NSFont.systemFont(ofSize: 12, weight: .semibold)
    public static let chapterBookTracking: CGFloat = 12 * 0.16
    public static func chapterNumber(readingSize pt: CGFloat) -> NSFont { latin(size: pt * 3.8, weight: .medium) }
}
