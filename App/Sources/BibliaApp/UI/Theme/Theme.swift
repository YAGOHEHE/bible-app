import BibliaCore
import SwiftUI

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
        background: .hex(0xFFFFFF), surface: .hex(0xF5F5F7),
        textPrimary: .hex(0x1D1D1F), textSecondary: .hex(0x48484F), textMuted: .hex(0x66666E),
        accent: .hex(0x3447A0), onAccent: .hex(0xFFFFFF), verseNumber: .hex(0x6A5A8E),
        heading: .hex(0x2C3470), strongUnderline: .hex(0x946B00),
        searchHighlight: .hex(0xFFE17A), selection: .hex(0xC9DAFF),
        border: .hex(0xD8D8DE), borderInput: .hex(0x85858F), focusRing: .hex(0x3447A0),
        danger: .hex(0xB3261E),
        versionAccent: [.hex(0x3447A0), .hex(0x1F6B45), .hex(0x9A4B00)],
        highlight: highlights([0xFFF3B0, 0xCDEFC8, 0xB8E6F2, 0xFFD3E2, 0xFFDDB8], selection: 0xC9DAFF).0,
        highlightSelected: highlights([0xFFF3B0, 0xCDEFC8, 0xB8E6F2, 0xFFD3E2, 0xFFDDB8], selection: 0xC9DAFF).1,
        bookmarkMarker: .hex(0xB5441F))

    static let dark = ThemePalette(
        background: .hex(0x1C1C1E), surface: .hex(0x2A2A2D),
        textPrimary: .hex(0xECECEF), textSecondary: .hex(0xC2C2CA), textMuted: .hex(0x9C9CA6),
        accent: .hex(0x9DB0FF), onAccent: .hex(0x10163A), verseNumber: .hex(0xA99BD0),
        heading: .hex(0xC9D1FF), strongUnderline: .hex(0xD9B24A),
        searchHighlight: .hex(0x6E5A0B), selection: .hex(0x2F4A80),
        border: .hex(0x3D3D42), borderInput: .hex(0x7C7C86), focusRing: .hex(0x9DB0FF),
        danger: .hex(0xFF8F86),
        versionAccent: [.hex(0x9DB0FF), .hex(0x8FD1A5), .hex(0xE0B070)],
        highlight: highlights([0x5A4E12, 0x1F5A33, 0x1C5468, 0x6B2A47, 0x6B3F14], selection: 0x2F4A80).0,
        highlightSelected: highlights([0x5A4E12, 0x1F5A33, 0x1C5468, 0x6B2A47, 0x6B3F14], selection: 0x2F4A80).1,
        bookmarkMarker: .hex(0xFF9E6B))

    static let sepia = ThemePalette(
        background: .hex(0xF4ECD8), surface: .hex(0xEADFC4),
        textPrimary: .hex(0x3B2F22), textSecondary: .hex(0x54442F), textMuted: .hex(0x6B5A44),
        accent: .hex(0x8A3B1E), onAccent: .hex(0xFFF8E8), verseNumber: .hex(0x7C5B3A),
        heading: .hex(0x6B2E14), strongUnderline: .hex(0x8A6414),
        searchHighlight: .hex(0xEFCB62), selection: .hex(0xDCC48E),
        border: .hex(0xD2C4A2), borderInput: .hex(0x85704F), focusRing: .hex(0x8A3B1E),
        danger: .hex(0xA3271B),
        versionAccent: [.hex(0x8A3B1E), .hex(0x3F6B3A), .hex(0x6A5A00)],
        highlight: highlights([0xF5E39A, 0xCFE0A8, 0xB5D5D3, 0xEBC3C0, 0xEBC08A], selection: 0xDCC48E).0,
        highlightSelected: highlights([0xF5E39A, 0xCFE0A8, 0xB5D5D3, 0xEBC3C0, 0xEBC08A], selection: 0xDCC48E).1,
        bookmarkMarker: .hex(0xA3401C))
}

struct Theme {
    let palette: ThemePalette
    let fontScale: Double
    let isSepia: Bool

    static let baseSize: CGFloat = 17

    func readingFont(latin: Bool, size: CGFloat = Theme.baseSize) -> Font {
        let s = size * fontScale
        return latin ? .system(size: s, design: .serif) : .custom("Songti SC", size: s)
    }
    /// Interlineado extra (SwiftUI suma a la altura natural ~1,2).
    func lineSpacing(latin: Bool) -> CGFloat {
        Theme.baseSize * fontScale * ((latin ? 1.55 : 1.85) - 1.2)
    }
    var pt: CGFloat { Theme.baseSize * fontScale }
    var verseNumberFont: Font { .system(size: pt * 0.62, weight: .semibold).monospacedDigit() }
    var verseNumberBaseline: CGFloat { pt * 0.38 }
    var headingFont: Font { .system(size: pt * 0.92, weight: .semibold, design: .serif) }
    var chapterTitleFont: Font { .system(size: pt * 1.6, weight: .bold, design: .serif) }
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
