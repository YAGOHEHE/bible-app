import Testing
import AppKit
import Foundation
@testable import ClassicKit
@testable import BibliaCore

@Suite struct BuilderTests {
    static let style = ReaderStyle(palette: .light, fontScale: 1.0, latin: true, perVerse: false)

    static func items() -> [DisplayVerse] {
        [DisplayVerse(number: 1, endNumber: 1, text: "Alpha line", headings: ["Primer título"], headingKinds: ["s1"]),
         DisplayVerse(number: 2, endNumber: 2, text: "Beta line", headings: [], headingKinds: []),
         DisplayVerse(number: 3, endNumber: 4, text: "Gamma merged", headings: ["Salmo de David"], headingKinds: ["d"])]
    }

    static func layout() -> [LayoutPiece] {
        [LayoutPiece(seq: 0, kind: "p", level: 1, verse: 1, text: "Alpha line"),
         LayoutPiece(seq: 1, kind: "q", level: 2, verse: 2, text: "Beta line"),
         LayoutPiece(seq: 2, kind: "q", level: 1, verse: 3, text: "Gamma merged")]
    }

    static func build(mode: ChapterBuilder.Mode = .book, headings: Bool = true, style: ReaderStyle = style) -> BuiltChapter {
        let blocks = ChapterBuilder.blocks(items: items(), layout: layout(), mode: mode, showHeadings: headings)
        return ChapterAttributedBuilder.build(title: "Juan 3", blocks: blocks, style: style)
    }

    @Test func titleAndHeadingsPresent() {
        let s = Self.build().text.string
        #expect(s.hasPrefix("JUAN\n3\n"))      // Códice: libro en mayúsculas + número grande
        #expect(s.contains("Primer título\n"))
        #expect(s.contains("Salmo de David\n"))
        #expect(!Self.build(headings: false).text.string.contains("Primer título"))
    }

    @Test func headingHierarchyFonts() {
        let b = Self.build()
        let t = b.text
        let r1 = (t.string as NSString).range(of: "Primer título")
        let r2 = (t.string as NSString).range(of: "Salmo de David")
        let body = t.attribute(.font, at: (t.string as NSString).range(of: "Alpha line").location, effectiveRange: nil) as? NSFont
        let f1 = t.attribute(.font, at: r1.location, effectiveRange: nil) as? NSFont
        let f2 = t.attribute(.font, at: r2.location, effectiveRange: nil) as? NSFont
        #expect(f1 != nil && f2 != nil && body != nil)
        #expect(NSFontManager.shared.traits(of: f1!).contains(.boldFontMask))
        #expect(f1!.pointSize < body!.pointSize)
        #expect(f2!.pointSize == f1!.pointSize)   // d: 0,92 em como s1
        let c1 = t.attribute(.foregroundColor, at: r1.location, effectiveRange: nil) as? NSColor
        let c2 = t.attribute(.foregroundColor, at: r2.location, effectiveRange: nil) as? NSColor
        #expect(c1 == ReaderPalette.light.heading)
        #expect(c2 == ReaderPalette.light.textSecondary)
    }

    @Test func superscriptVerseNumbers() {
        let b = Self.build()
        let t = b.text
        var labels: [String] = []
        t.enumerateAttribute(.bibliaVerseNumber, in: NSRange(location: 0, length: t.length)) { v, r, _ in
            guard v != nil else { return }
            labels.append((t.string as NSString).substring(with: r).trimmingCharacters(in: .whitespaces))
            let off = t.attribute(.baselineOffset, at: r.location, effectiveRange: nil) as? CGFloat
            let f = t.attribute(.font, at: r.location, effectiveRange: nil) as? NSFont
            let body = t.attribute(.font, at: r.location + r.length, effectiveRange: nil) as? NSFont
            #expect((off ?? 0) > 0)
            #expect(f!.pointSize < body!.pointSize * 0.7)
        }
        #expect(labels == ["1", "2", "3–4"])    // fusionados: «3–4»
    }

    @Test func poetryIndentAndHang() {
        let t = Self.build().text
        let ns = t.string as NSString
        let p2 = t.attribute(.paragraphStyle, at: ns.range(of: "Beta").location, effectiveRange: nil) as? NSParagraphStyle
        let p3 = t.attribute(.paragraphStyle, at: ns.range(of: "Gamma").location, effectiveRange: nil) as? NSParagraphStyle
        let p1 = t.attribute(.paragraphStyle, at: ns.range(of: "Alpha").location, effectiveRange: nil) as? NSParagraphStyle
        #expect(p1!.firstLineHeadIndent == 0 && p1!.headIndent == 0)
        let pt = Self.style.pt
        #expect(abs(p2!.firstLineHeadIndent - (pt * 1.5 + pt * 0.4)) < 0.01)   // nivel 2
        #expect(abs(p3!.firstLineHeadIndent - pt * 0.4) < 0.01)               // nivel 1
        #expect(abs((p2!.headIndent - p2!.firstLineHeadIndent) - pt * 1.5) < 0.01)  // sangría francesa
    }

    @Test func perVerseModeOneParagraphEach() {
        let b = Self.build(mode: .perVerse, style: ReaderStyle(palette: .light, fontScale: 1, latin: true, perVerse: true))
        let lines = b.text.string.split(separator: "\n").map(String.init)
        // libro + número de capítulo + 2 títulos + 3 versículos
        #expect(lines.count == 7)
        #expect(lines.contains { $0.contains("Gamma merged") && $0.hasPrefix("3–4") })
    }

    @Test func verseRangesAndAnchors() {
        let b = Self.build()
        #expect(b.verseRanges.keys.sorted() == [1, 2, 3])
        let s = b.text.string as NSString
        #expect(s.substring(with: b.verseRanges[2]!).contains("Beta line"))
        #expect(b.scrollTargets[1] == 0)                       // el primero muestra el título del capítulo
        // el versículo 3 se ancla en su título «Salmo de David»
        #expect(b.scrollTargets[3] == s.range(of: "Salmo de David").location)
        #expect(b.verse(atLocation: 0) == 1)
        #expect(b.verse(atLocation: b.verseRanges[3]!.location + 2) == 3)
        // línea que contiene el final del 2 y el inicio del 3 -> 3 (ancla estable)
        let r2 = b.verseRanges[2]!, r3 = b.verseRanges[3]!
        #expect(b.verse(forLine: NSRange(location: r2.location + 2, length: r3.location + 3 - (r2.location + 2))) == 3)
        #expect(b.verse(forLine: NSRange(location: r3.location + 1, length: 4)) == 3)
        #expect(b.verses(intersecting: NSRange(location: b.verseRanges[2]!.location, length: 3)) == [2])
    }

    @Test func midParagraphVerseAnchorsAtItsOwnLabel() {
        // Dos versículos en el mismo párrafo: el segundo se ancla en su número, no al inicio del párrafo.
        let items = [DisplayVerse(number: 1, endNumber: 1, text: "Uno", headings: []),
                     DisplayVerse(number: 2, endNumber: 2, text: "Dos", headings: [])]
        let layout = [LayoutPiece(seq: 0, kind: "p", level: 1, verse: 1, text: "Uno"),
                      LayoutPiece(seq: 1, kind: "+", level: 1, verse: 2, text: "Dos")]
        let blocks = ChapterBuilder.blocks(items: items, layout: layout, mode: .book, showHeadings: true)
        let b = ChapterAttributedBuilder.build(title: "T", blocks: blocks, style: Self.style)
        #expect(blocks.count == 1)
        #expect(b.scrollTargets[2] == b.verseRanges[2]!.location)
        #expect(b.scrollTargets[2]! > b.scrollTargets[1]!)
    }

    @Test func scaleAndChineseFonts() {
        let big = ReaderStyle(palette: .dark, fontScale: 2.0, latin: false, perVerse: false)
        let b = Self.build(style: big)
        let f = b.text.attribute(.font, at: (b.text.string as NSString).range(of: "Alpha").location, effectiveRange: nil) as? NSFont
        #expect(f!.pointSize == 38)      // 19 pt base × 2,0
        let c = b.text.attribute(.foregroundColor, at: (b.text.string as NSString).range(of: "Alpha").location, effectiveRange: nil) as? NSColor
        #expect(c == ReaderPalette.dark.textPrimary)
        #expect(big.lineSpacing > ReaderStyle(palette: .dark, fontScale: 2.0, latin: true, perVerse: false).lineSpacing)
    }

    @Test func codiceHeaderAndVerseNumberStyle() {
        let b = Self.build()
        let t = b.text
        let book = t.attributes(at: 0, effectiveRange: nil)
        #expect((book[.font] as? NSFont)?.pointSize == 12)
        #expect(book[.foregroundColor] as? NSColor == Self.style.palette.textMuted)
        #expect(abs((book[.kern] as? CGFloat ?? 0) - 12 * 0.16) < 0.001)
        let num = t.attributes(at: ("JUAN\n" as NSString).length, effectiveRange: nil)
        #expect(abs((num[.font] as? NSFont)!.pointSize - 3.8 * Self.style.pt) < 0.01)
        #expect(num[.foregroundColor] as? NSColor == Self.style.palette.accent)
        let vn = (b.text.string as NSString).range(of: "Alpha").location
        var found = false
        t.enumerateAttribute(.bibliaVerseNumber, in: NSRange(location: 0, length: min(vn, t.length)), options: []) { v, r, stop in
            guard v != nil else { return }
            let a = t.attributes(at: r.location, effectiveRange: nil)
            #expect(abs((a[.font] as? NSFont)!.pointSize - 0.58 * Self.style.pt) < 0.01)
            #expect(abs((a[.baselineOffset] as? CGFloat ?? 0) - 0.40 * Self.style.pt) < 0.01)
            #expect(a[.foregroundColor] as? NSColor == Self.style.palette.verseNumber)
            found = true; stop.pointee = true
        }
        #expect(found)
        #expect(ReaderStyle.baseSize == 19 && ReaderFonts.columnWidth == 640)
    }

    @Test func codicePaletteMatchesTokens() {
        #expect(ReaderPalette.light.background == ReaderPalette.hex(0xFBFAF7))
        #expect(ReaderPalette.dark.accent == ReaderPalette.hex(0xEE8B76))
        #expect(ReaderPalette.sepia.onAccent == ReaderPalette.hex(0xFFF8EC))
        #expect(ReaderPalette.light.highlight(.orange) == ReaderPalette.hex(0xF1DCC6))
        #expect(ReaderPalette.dark.versionColor(1) == ReaderPalette.hex(0x8FB8E0))
        #expect(ReaderPalette.sepia.strongUnderline == ReaderPalette.hex(0xB9A47C))
    }

    @Test func paletteAndFontScale() {
        #expect(FontScale.clamp(0.1) == 0.8 && FontScale.clamp(5) == 2.0 && FontScale.clamp(1.04) == 1.0)
        #expect(ReaderPalette.resolve(.dark).isDark && !ReaderPalette.resolve(.sepia).isDark)
        #expect(ReaderFonts.latin(size: 17).pointSize == 17)
        #expect(ReaderFonts.cjk(size: 17).pointSize == 17)
    }
}
