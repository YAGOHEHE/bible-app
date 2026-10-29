import AppKit
import BibliaCore

public extension NSAttributedString.Key {
    /// Número de versículo (Int) al que pertenece el texto. Lo usan «copiar con referencia», el ancla y L4.
    static let bibliaVerse = NSAttributedString.Key("org.biblia.clasica.verse")
    /// Marca los números de versículo en superíndice.
    static let bibliaVerseNumber = NSAttributedString.Key("org.biblia.clasica.verseNumber")
}

public struct ReaderStyle {
    public var palette: ReaderPalette
    public var fontScale: Double
    public var latin: Bool
    /// Un versículo por línea (en vez de párrafos de la tabla `layout`).
    public var perVerse: Bool
    public static let baseSize: CGFloat = 17

    /// Anotaciones del capítulo: el constructor inserta ⚑ y ✎ (los resaltados se pintan aparte, ver `AnnotationOverlays`).
    public var annotations = ChapterAnnotations()

    public init(palette: ReaderPalette, fontScale: Double, latin: Bool, perVerse: Bool) {
        self.palette = palette; self.fontScale = fontScale; self.latin = latin; self.perVerse = perVerse
    }
    public var pt: CGFloat { ReaderStyle.baseSize * CGFloat(fontScale) }
    /// Interlineado extra (AppKit lo suma a la altura natural de la fuente).
    public var lineSpacing: CGFloat { pt * ((latin ? 1.55 : 1.85) - 1.2) }
}

/// Capítulo ya maquetado: texto + posiciones de cada versículo.
public struct BuiltChapter {
    public let text: NSAttributedString
    /// Rango de cada versículo (desde su número hasta el final de su texto; trozos separados por poesía se unen).
    public let verseRanges: [Int: NSRange]
    /// Posición a la que desplazarse para ver el versículo (incluye los títulos que lo preceden).
    public let scrollTargets: [Int: Int]
    /// (posición, versículo) ordenado por posición.
    public let verseStarts: [(location: Int, verse: Int)]

    /// Versículo visible en la posición `loc` (el último que empieza antes).
    public func verse(atLocation loc: Int) -> Int? {
        guard let first = verseStarts.first else { return nil }
        var lo = 0, hi = verseStarts.count - 1, ans = first.verse
        while lo <= hi {
            let mid = (lo + hi) / 2
            if verseStarts[mid].location <= loc { ans = verseStarts[mid].verse; lo = mid + 1 } else { hi = mid - 1 }
        }
        return ans
    }

    /// Versículo «superior» de una línea visible: el primero que empieza dentro de ella; si ninguno empieza, el que continúa.
    /// (Así el ancla es estable al cambiar el tamaño de letra: no retrocede un versículo en cada paso.)
    public func verse(forLine line: NSRange) -> Int? {
        if let s = verseStarts.first(where: { $0.location >= line.location && $0.location < NSMaxRange(line) }) { return s.verse }
        return verse(atLocation: line.location)
    }

    /// Versículos cuyo texto toca `range`.
    public func verses(intersecting range: NSRange) -> [Int] {
        guard range.length > 0 else { return [] }
        return verseRanges.filter { NSIntersectionRange($0.value, range).length > 0 }.map(\.key).sorted()
    }
}

/// Texto que se inserta tras un bloque (líneas de glosa bajo un versículo).
public struct BlockExtra {
    public init(text: NSAttributedString, verse: Int, trailing: CGFloat) { self.text = text; self.verse = verse; self.trailing = trailing }
    public let text: NSAttributedString
    public let verse: Int
    /// Interlineado de la última línea (se descuenta de la separación del bloque siguiente).
    public let trailing: CGFloat
}

public enum ChapterAttributedBuilder {
    public static func build(title: String, blocks: [BookBlock], style s: ReaderStyle,
                             extras: [Int: BlockExtra] = [:], afterTitle: NSAttributedString? = nil) -> BuiltChapter {
        let pt = s.pt, pal = s.palette
        let body = ReaderFonts.reading(latin: s.latin, size: pt)
        let out = NSMutableAttributedString()
        var ranges: [Int: NSRange] = [:]
        var targets: [Int: Int] = [:]
        let kern: CGFloat = s.latin ? 0 : pt * 0.02

        func para(before: CGFloat = 0, after: CGFloat = 0, indent: CGFloat = 0, hang: CGFloat = 0,
                  align: NSTextAlignment = .natural, lineSpacing: CGFloat = 0) -> NSParagraphStyle {
            let p = NSMutableParagraphStyle()
            p.paragraphSpacingBefore = before
            p.paragraphSpacing = after
            p.firstLineHeadIndent = indent
            p.headIndent = indent + hang
            p.alignment = align
            p.lineSpacing = lineSpacing
            p.lineBreakMode = .byWordWrapping
            return p
        }
        func extend(_ verse: Int, _ r: NSRange) {
            if let old = ranges[verse] { ranges[verse] = NSUnionRange(old, r) } else { ranges[verse] = r }
        }

        // Título del capítulo
        let titleFont = ReaderFonts.traits(ReaderFonts.reading(latin: s.latin, size: pt * 1.6), bold: true)
        out.append(NSAttributedString(string: title + "\n", attributes: [
            .font: titleFont, .foregroundColor: pal.textPrimary,
            .paragraphStyle: para(after: pt * 0.8)]))
        if let n = afterTitle { out.append(n) }

        // AppKit suma `lineSpacing` también tras la última línea de cada párrafo; se descuenta de la separación
        // superior del párrafo siguiente para que el ritmo vertical sea el del lector SwiftUI.
        var trailing: CGFloat = 0
        var prev: BookBlock?          // último bloque visible (sin contar los vacíos)
        var blankBefore = false
        var pendingTarget: Int?       // inicio de los títulos que preceden al siguiente texto
        // Último trozo de cada versículo (ahí va ✎) y notas que ya tienen icono.
        var lastPiece: [Int: [Int]] = [:]
        for (bi, b) in blocks.enumerated() where b.kind == .prose || b.kind == .poetry || b.kind == .list {
            for (pi, p) in b.pieces.enumerated() { lastPiece[p.verse] = [bi, pi] }
        }
        var shownNotes = Set<Int64>()
        for (bi, b) in blocks.enumerated() {
            switch b.kind {
            case .blank:
                blankBefore = true
            case .heading:
                let k = b.headingKind
                var size: CGFloat = 0.92; var bold = true, italic = false, center = false; var color = pal.heading
                switch k {
                case "ms": size = 1.15; center = true
                case "s2": size = 0.85; italic = true
                case "d": size = 0.92; bold = false; italic = true; color = pal.textSecondary
                case "r": size = 0.78; bold = false; italic = true; color = pal.textMuted
                default: break
                }
                if !s.latin { italic = false }
                let before: CGFloat = prev == nil ? 0 : max(0, (k == "d" || k == "r" ? pt * 0.15 : pt * (k == "ms" ? 1.8 : 1.4)) - trailing)
                let after = pt * (k == "r" || k == "d" ? 0.3 : 0.5)
                let font = ReaderFonts.traits(ReaderFonts.reading(latin: s.latin, size: pt * size), bold: bold, italic: italic)
                if pendingTarget == nil { pendingTarget = out.length }
                out.append(NSAttributedString(string: (b.pieces.first?.text ?? "") + "\n", attributes: [
                    .font: font, .foregroundColor: color,
                    .paragraphStyle: para(before: before, after: after, align: center ? .center : .natural)]))
                prev = b; blankBefore = false; trailing = 0
            case .prose, .poetry, .list:
                // separación superior (misma regla que el lector SwiftUI)
                var gap: CGFloat = 0
                if let p = prev {
                    if s.perVerse { gap = p.kind == .heading ? 0 : pt * 0.35 }
                    else if b.kind == .poetry || b.kind == .list {
                        gap = (p.kind == .poetry || p.kind == .list) ? pt * 0.08 : (p.kind == .heading ? 0 : pt * 0.5)
                    } else {
                        gap = p.kind == .heading ? 0 : pt * (b.flush ? 0.5 : 0.7)
                    }
                    if blankBefore { gap = pt * 0.7 + (b.kind == .poetry || b.kind == .list ? pt * 0.08 : 0) }
                }
                let indent: CGFloat
                switch b.kind {
                case .poetry: indent = pt * 1.5 * CGFloat(max(0, b.level - 1)) + pt * 0.4
                case .list: indent = pt * 1.2 * CGFloat(b.level)
                default: indent = 0
                }
                let hang: CGFloat = (b.kind == .poetry || b.kind == .list) ? pt * 1.5 : 0
                let ls = (b.kind == .poetry || b.kind == .list) ? pt * 0.12 : s.lineSpacing
                let ps = para(before: max(0, gap - trailing), indent: indent, hang: hang, lineSpacing: ls)
                trailing = ls
                let blockStart = out.length
                for (i, piece) in b.pieces.enumerated() {
                    let start = out.length
                    let ann = s.annotations.forDisplayVerse(number: piece.verse, end: max(piece.verse, piece.end))
                    if piece.label != nil, ann.isBookmarked {
                        out.append(AnnotationOverlays.bookmarkFlag(verse: piece.verse, pt: pt, palette: pal, paragraph: ps))
                    }
                    if let l = piece.label {
                        out.append(NSAttributedString(string: l + "\u{2009}", attributes: [
                            .font: ReaderFonts.verseNumber(size: pt * 0.62), .foregroundColor: pal.verseNumber,
                            .baselineOffset: pt * 0.38, .paragraphStyle: ps,
                            .bibliaVerse: piece.verse, .bibliaVerseNumber: true]))
                    }
                    var attrs: [NSAttributedString.Key: Any] = [
                        .font: body, .foregroundColor: piece.text == "\u{2014}" ? pal.textMuted : pal.textPrimary, .paragraphStyle: ps, .bibliaVerse: piece.verse]
                    if kern != 0 { attrs[.kern] = kern }
                    var t = piece.text
                    if i < b.pieces.count - 1, s.latin { t += " " }
                    out.append(NSAttributedString(string: t, attributes: attrs))
                    if lastPiece[piece.verse] == [bi, i] {
                        for n in AnnotationOverlays.newNotes(ann, shown: &shownNotes) {
                            out.append(AnnotationOverlays.noteIcon(noteId: n.id, verse: piece.verse, pt: pt, palette: pal, paragraph: ps))
                        }
                    }
                    extend(piece.verse, NSRange(location: start, length: out.length - start))
                    if targets[piece.verse] == nil { targets[piece.verse] = pendingTarget ?? (i == 0 ? blockStart : start) }
                    pendingTarget = nil
                }
                var nl = NSAttributedString(string: "\n", attributes: [.font: body, .paragraphStyle: ps])
                if b.pieces.isEmpty { nl = NSAttributedString(string: "") }
                out.append(nl)
                prev = b; blankBefore = false
            }
            if let ex = extras[b.id] {
                let st = out.length
                out.append(ex.text)
                extend(ex.verse, NSRange(location: st, length: out.length - st))
                trailing = ex.trailing
            }
        }
        // El primer versículo siempre muestra el título del capítulo.
        if let first = ranges.keys.min() { targets[first] = 0 }
        let starts = ranges.map { (location: $0.value.location, verse: $0.key) }.sorted { $0.location < $1.location }
        return BuiltChapter(text: out, verseRanges: ranges, scrollTargets: targets, verseStarts: starts)
    }
}
