import AppKit
import BibliaCore

public extension NSAttributedString.Key {
    /// Marca el texto de las glosas (líneas bajo el versículo principal): los resaltados no las pintan.
    static let bibliaGloss = NSAttributedString.Key("org.biblia.clasica.gloss")
}

/// Resaltados, selección, marcadores (⚑) y notas (✎) sobre el texto maquetado.
public enum AnnotationOverlays {
    public static let bookmarkGlyph = "\u{2691}"   // ⚑
    public static let noteGlyph = "\u{270E}"       // ✎

    // MARK: decoración que cambia el texto (se inserta al maquetar)

    /// ⚑ delante del número de un versículo con marcador.
    public static func bookmarkFlag(verse: Int, pt: CGFloat, palette: ReaderPalette, paragraph: NSParagraphStyle) -> NSAttributedString {
        NSAttributedString(string: bookmarkGlyph, attributes: [
            .font: NSFont.systemFont(ofSize: pt * 0.8), .foregroundColor: palette.bookmarkMarker,
            .baselineOffset: pt * 0.3, .paragraphStyle: paragraph, .bibliaVerse: verse, .bibliaVerseNumber: true])
    }

    /// ✎ (enlace `note://ID`) tras el texto de un versículo con nota.
    public static func noteIcon(noteId: Int64, verse: Int, pt: CGFloat, palette: ReaderPalette, paragraph: NSParagraphStyle) -> NSAttributedString {
        var attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: pt * 0.8), .foregroundColor: palette.accent,
            .paragraphStyle: paragraph, .bibliaVerse: verse, .toolTip: "Abrir la nota"]
        if let u = URL(string: "\(NoteLink.scheme)://\(noteId)") { attrs[.link] = u }
        return NSAttributedString(string: "\u{2009}" + noteGlyph, attributes: attrs)
    }

    /// Notas de `ann` que aún no tienen icono (cada nota lleva uno solo, en el primer versículo que cubre).
    public static func newNotes(_ ann: VerseAnnotations, shown: inout Set<Int64>) -> [Note] {
        var out: [Note] = []
        for n in ann.notes where !shown.contains(n.id) { shown.insert(n.id); out.append(n) }
        return out
    }

    // MARK: fondos (resaltado + selección), sin cambiar el texto

    /// Mezcla de selección y resaltado: la selección se superpone al color del resaltado.
    public static func blended(highlight: NSColor?, selected: Bool, palette: ReaderPalette) -> NSColor? {
        switch (highlight, selected) {
        case (nil, false): return nil
        case (let h?, false): return h
        case (nil, true): return palette.selection
        case (let h?, true):
            return palette.selection.blended(withFraction: palette.isDark ? 0.42 : 0.62, of: h) ?? palette.selection
        }
    }

    /// Color de fondo de un versículo.
    public static func background(_ ann: VerseAnnotations, selected: Bool, palette: ReaderPalette) -> NSColor? {
        blended(highlight: ann.color.map { palette.highlight($0) }, selected: selected, palette: palette)
    }

    /// Repinta los fondos de resaltado/selección del texto: quita todos los `.backgroundColor` y los vuelve a poner
    /// (el resaltado de búsqueda se aplica después, encima). No toca saltos de línea ni líneas de glosa.
    /// `annotations(key)` da las anotaciones del versículo mostrado (incluidos los fusionados «20–21»).
    @discardableResult
    public static func applyBackgrounds(to text: NSMutableAttributedString, ranges: [Int: NSRange], selected: Set<Int>,
                                        annotations: (Int) -> VerseAnnotations, palette: ReaderPalette) -> Int {
        let whole = NSRange(location: 0, length: text.length)
        let ns = text.string as NSString
        var painted = 0
        text.beginEditing()
        text.removeAttribute(.backgroundColor, range: whole)
        for (key, r) in ranges where NSMaxRange(r) <= text.length && r.length > 0 {
            guard let color = background(annotations(key), selected: selected.contains(key), palette: palette) else { continue }
            text.enumerateAttribute(.bibliaGloss, in: r, options: []) { value, run, _ in
                if value != nil { return }
                var start = run.location
                let end = NSMaxRange(run)
                var i = start
                while i <= end {
                    if i == end || ns.character(at: i) == 10 {      // trocear por saltos de línea
                        if i > start { text.addAttribute(.backgroundColor, value: color, range: NSRange(location: start, length: i - start)); painted += 1 }
                        start = i + 1
                    }
                    i += 1
                }
            }
        }
        text.endEditing()
        return painted
    }
}
