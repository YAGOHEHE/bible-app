import AppKit
import BibliaCore

/// Colores de un tema de lectura (valores de replica/design/tokens.json).
public struct ReaderPalette {
    public let isDark: Bool
    public let background, surface, textPrimary, textSecondary, textMuted: NSColor
    public let accent, verseNumber, heading, selection, border: NSColor
    /// Subrayado punteado de las palabras Strong (token `strong-underline`).
    public let strongUnderline: NSColor
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

    public static let light = ReaderPalette(
        isDark: false, background: hex(0xFFFFFF), surface: hex(0xF5F5F7), textPrimary: hex(0x1D1D1F),
        textSecondary: hex(0x48484F), textMuted: hex(0x66666E), accent: hex(0x3447A0), verseNumber: hex(0x6A5A8E),
        heading: hex(0x2C3470), selection: hex(0xC9DAFF), border: hex(0xD8D8DE), strongUnderline: hex(0x946B00),
        version: [hex(0x3447A0), hex(0x1F6B45), hex(0x9A4B00)],
        highlights: [.yellow: hex(0xFFF3B0), .green: hex(0xCDEFC8), .blue: hex(0xB8E6F2), .pink: hex(0xFFD3E2), .orange: hex(0xFFDDB8)],
        bookmarkMarker: hex(0xB5441F))
    public static let dark = ReaderPalette(
        isDark: true, background: hex(0x1C1C1E), surface: hex(0x2A2A2D), textPrimary: hex(0xECECEF),
        textSecondary: hex(0xC2C2CA), textMuted: hex(0x9C9CA6), accent: hex(0x9DB0FF), verseNumber: hex(0xA99BD0),
        heading: hex(0xC9D1FF), selection: hex(0x2F4A80), border: hex(0x3D3D42), strongUnderline: hex(0xD9B24A),
        version: [hex(0x9DB0FF), hex(0x8FD1A5), hex(0xE0B070)],
        highlights: [.yellow: hex(0x5A4E12), .green: hex(0x1F5A33), .blue: hex(0x1C5468), .pink: hex(0x6B2A47), .orange: hex(0x6B3F14)],
        bookmarkMarker: hex(0xFF9E6B))
    public static let sepia = ReaderPalette(
        isDark: false, background: hex(0xF4ECD8), surface: hex(0xEADFC4), textPrimary: hex(0x3B2F22),
        textSecondary: hex(0x54442F), textMuted: hex(0x6B5A44), accent: hex(0x8A3B1E), verseNumber: hex(0x7C5B3A),
        heading: hex(0x6B2E14), selection: hex(0xDCC48E), border: hex(0xD2C4A2), strongUnderline: hex(0x8A6414),
        version: [hex(0x8A3B1E), hex(0x3F6B3A), hex(0x6A5A00)],
        highlights: [.yellow: hex(0xF5E39A), .green: hex(0xCFE0A8), .blue: hex(0xB5D5D3), .pink: hex(0xEBC3C0), .orange: hex(0xEBC08A)],
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

/// Fuentes de lectura con alternativas que existen en 10.13.
public enum ReaderFonts {
    /// Serif latino: New York (10.15+) o Iowan Old Style / Georgia / Times New Roman.
    public static func latin(size: CGFloat) -> NSFont {
        if #available(macOS 10.15, *) {
            if let d = NSFont.systemFont(ofSize: size).fontDescriptor.withDesign(.serif),
               let f = NSFont(descriptor: d, size: size) { return f }
        }
        for n in ["Iowan Old Style", "Georgia", "Times New Roman"] {
            if let f = NSFont(name: n, size: size) { return f }
        }
        return NSFont.systemFont(ofSize: size)
    }

    /// Chino: Songti SC (宋体); alternativas PingFang SC, STSong, Hiragino Sans GB.
    public static func cjk(size: CGFloat) -> NSFont {
        for n in ["Songti SC", "STSong", "PingFang SC", "Hiragino Sans GB"] {
            if let f = NSFont(name: n, size: size) { return f }
        }
        return NSFont.systemFont(ofSize: size)
    }

    public static func reading(latin isLatin: Bool, size: CGFloat) -> NSFont { isLatin ? latin(size: size) : cjk(size: size) }

    public static func traits(_ f: NSFont, bold: Bool = false, italic: Bool = false) -> NSFont {
        var out = f
        if bold { out = NSFontManager.shared.convert(out, toHaveTrait: .boldFontMask) }
        if italic { out = NSFontManager.shared.convert(out, toHaveTrait: .italicFontMask) }
        return out
    }

    /// Número de versículo: sans semibold con dígitos tabulares, 0,62 em.
    public static func verseNumber(size: CGFloat) -> NSFont {
        let f = NSFont.systemFont(ofSize: size, weight: .semibold)
        let d = f.fontDescriptor.addingAttributes([
            .featureSettings: [[NSFontDescriptor.FeatureKey.typeIdentifier: 6, NSFontDescriptor.FeatureKey.selectorIdentifier: 0]]
        ])
        return NSFont(descriptor: d, size: size) ?? f
    }
}
