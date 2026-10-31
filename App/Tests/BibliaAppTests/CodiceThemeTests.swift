import Testing
import SwiftUI
import AppKit
import BibliaCore
@testable import BibliaApp

/// Rediseño «Códice»: paleta = tokens.json, contraste, Literata y fondos redondeados del lector.
@Suite struct CodiceThemeTests {
    private static func hex(_ c: Color) -> String {
        let n = NSColor(c).usingColorSpace(.sRGB)!
        func b(_ v: CGFloat) -> Int { Int((v * 255).rounded()) }
        return String(format: "#%02X%02X%02X", b(n.redComponent), b(n.greenComponent), b(n.blueComponent))
    }
    private static func lum(_ h: String) -> Double {
        let v = UInt32(h.dropFirst(), radix: 16)!
        func ch(_ s: UInt32) -> Double {
            let c = Double((v >> s) & 0xFF) / 255
            return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * ch(16) + 0.7152 * ch(8) + 0.0722 * ch(0)
    }
    private static func ratio(_ a: String, _ b: String) -> Double {
        let (x, y) = (lum(a), lum(b)); return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }
    private static func tokens() throws -> [String: [String: String]] {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("replica/design/tokens.json")
        let obj = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        return obj["color"] as! [String: [String: String]]
    }

    @Test func paletteMatchesTokensAndContrast() throws {
        let t = try Self.tokens()
        for (name, p) in [("light", ThemePalette.light), ("dark", .dark), ("sepia", .sepia)] {
            let c = t[name]!
            #expect(Self.hex(p.background) == c["background"])
            #expect(Self.hex(p.accent) == c["accent"])
            #expect(Self.hex(p.onAccent) == c["on-accent"])
            #expect(Self.hex(p.selection) == c["selection"])
            #expect(Self.hex(p.bookmarkMarker) == c["bookmark-marker"])
            for (i, v) in p.versionAccent.enumerated() { #expect(Self.hex(v) == c["version-\(i + 1)"]) }
            for (h, k) in zip(HighlightColor.allCases, ["yellow", "green", "blue", "pink", "orange"]) {
                #expect(Self.hex(p.highlight[h]!) == c["highlight-\(k)"], "\(name) \(k)")
            }
            let bg = Self.hex(p.background)
            for col in [p.textPrimary, p.textSecondary, p.textMuted, p.accent, p.verseNumber, p.heading, p.danger] + p.versionAccent {
                #expect(Self.ratio(Self.hex(col), bg) >= 4.5, "\(name) \(Self.hex(col))")
            }
            #expect(Self.ratio(Self.hex(p.borderInput), bg) >= 3, "\(name) borderInput")
            #expect(Self.ratio(Self.hex(p.onAccent), Self.hex(p.accent)) >= 4.5)
        }
    }

    @Test func literataRegistersAndSizesFollowSpec() {
        #expect(FontRegistry.registerBundledFonts() == FontRegistry.literataFiles.count)
        #expect(FontRegistry.literataAvailable)
        let th = Theme(palette: .light, fontScale: 1, isSepia: false)
        #expect(Theme.baseSize == 19 && Theme.readingColumnWidth == 640)
        #expect(th.readingNSFont(latin: true).familyName == "Literata")
        let f = th.readingNSFont(latin: true)
        // interlineado total = 1,72 × tamaño
        #expect(abs(Theme.naturalLineHeight(f) + th.lineSpacing(latin: true) - 19 * 1.72) < 1.01)
    }

    @Test func roundedBandsFollowHighlightedVerse() {
        let th = Theme(palette: .light, fontScale: 1, isSepia: false)
        var s = AttributedString("Uno dos tres cuatro cinco seis siete ocho nueve diez once doce trece catorce quince")
        let f = th.readingFont(latin: true), ns = th.readingNSFont(latin: true)
        s.font = f; s[MirrorFontKey.self] = ns
        let lo = s.index(s.startIndex, offsetByCharacters: 4), hi = s.index(s.startIndex, offsetByCharacters: 70)
        s[lo..<hi][RoundedBGKey.self] = RoundedBG(color: .yellow, radius: 3)
        #expect(s.hasRoundedBackgrounds)
        let bands = RoundedBackdropLayout.bands(for: s, width: 200, bodyFont: ns, lineSpacing: th.lineSpacing(latin: true), tracking: 0)
        #expect(bands.count >= 2)                     // varias líneas
        #expect(bands.allSatisfy { $0.rect.maxX <= 200.5 && $0.bg.radius == 3 })
        #expect(!s.strippingRoundedBackgrounds().runs.contains { $0.backgroundColor != nil })
    }
}
