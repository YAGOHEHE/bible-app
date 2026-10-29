import AppKit
import BibliaCore

/// Capas que se aplican al texto ya maquetado de un capítulo: palabras Strong y resaltado de búsqueda.
/// Trabajan sobre el `NSMutableAttributedString` (NSTextStorage) y los rangos por versículo de `BuiltChapter`,
/// de modo que no dependen de cómo se partió el versículo en párrafos/líneas de poesía.
public enum ReaderOverlays {
    public static let strongUnderline: NSNumber = NSNumber(value: NSUnderlineStyle.single.rawValue | NSUnderlineStyle.patternDot.rawValue)

    /// Subraya con puntos las palabras etiquetadas y las hace enlaces `strong://G25?v=16&s=14`.
    /// `verseText(n)` devuelve el texto completo del versículo (los tramos son desplazamientos sobre él).
    /// Devuelve cuántas palabras se marcaron (una palabra que no se localiza se salta sin romper el resto).
    @discardableResult
    public static func applyStrong(to text: NSMutableAttributedString, ranges: [Int: NSRange],
                                   spans: [Int: [StrongSpan]], verseText: (Int) -> String?,
                                   palette: ReaderPalette) -> Int {
        var marked = 0
        let ns = text.string as NSString
        text.beginEditing()
        for (verse, list) in spans {
            guard let r = ranges[verse], NSMaxRange(r) <= ns.length, let full = verseText(verse) else { continue }
            let chars = Array(full)
            var cursor = r.location
            for sp in list.sorted(by: { $0.start < $1.start }) {
                guard sp.start >= 0, sp.end <= chars.count else { continue }
                let word = String(chars[sp.start..<sp.end])
                guard !word.isEmpty else { continue }
                let from = NSRange(location: cursor, length: NSMaxRange(r) - cursor)
                guard from.length > 0 else { break }
                var found = ns.range(of: word, options: [], range: from)
                while found.location != NSNotFound, !isWordBoundary(ns, found) {
                    let next = NSRange(location: found.location + 1, length: NSMaxRange(r) - found.location - 1)
                    if next.length <= 0 { found = NSRange(location: NSNotFound, length: 0); break }
                    found = ns.range(of: word, options: [], range: next)
                }
                guard found.location != NSNotFound, let url = StrongLink.url(sp, verse: verse) else { continue }
                text.addAttributes([
                    .link: url,
                    .underlineStyle: strongUnderline,
                    .underlineColor: palette.strongUnderline,
                ], range: found)
                cursor = NSMaxRange(found)
                marked += 1
            }
        }
        text.endEditing()
        return marked
    }

    private static func isWordBoundary(_ s: NSString, _ r: NSRange) -> Bool {
        func isWord(_ i: Int) -> Bool {
            guard i >= 0, i < s.length, let u = Unicode.Scalar(s.character(at: i)) else { return false }
            return CharacterSet.letters.contains(u) || CharacterSet.decimalDigits.contains(u)
        }
        return !isWord(r.location - 1) && !isWord(NSMaxRange(r))
    }

    /// Resalta las coincidencias de la búsqueda dentro de los versículos indicados (o de todo el capítulo).
    /// Devuelve el número de coincidencias pintadas.
    @discardableResult
    public static func applyHighlight(to text: NSMutableAttributedString, ranges: [Int: NSRange], terms: [String],
                                      palette: ReaderPalette) -> Int {
        guard !terms.isEmpty else { return 0 }
        var n = 0
        text.beginEditing()
        for (_, r) in ranges where NSMaxRange(r) <= text.length {
            let s = (text.string as NSString).substring(with: r)
            for m in SearchHighlighter.ranges(in: s, terms: terms) {
                let local = NSRange(m, in: s)
                text.addAttribute(.backgroundColor, value: palette.searchMatch,
                                  range: NSRange(location: r.location + local.location, length: local.length))
                n += 1
            }
        }
        text.endEditing()
        return n
    }
}

public extension ReaderPalette {
    /// Fondo de las coincidencias de búsqueda (en el texto y en la lista).
    var searchMatch: NSColor { isDark ? ReaderPalette.hex(0x6B5A1E) : ReaderPalette.hex(0xFFE58A) }
    /// Fondo de la «pastilla» G25 / H430.
    var pillBackground: NSColor { isDark ? ReaderPalette.hex(0x9DB0FF) : ReaderPalette.hex(0x3447A0) }
    var pillText: NSColor { isDark ? ReaderPalette.hex(0x10163A) : NSColor.white }
}
