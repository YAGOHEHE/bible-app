import AppKit
import BibliaCore

public func languageLabel(_ code: String) -> String {
    switch code { case "zh": return "中文"; case "es": return "Español"; case "en": return "English"; default: return code.uppercased() }
}

// MARK: - Columnas limpias

public struct BuiltColumns {
    public struct Column {
        public let id: String
        public let language: String
        public let text: NSAttributedString
        /// Rango del contenido de cada fila (clave = número de fila).
        public let verseRanges: [Int: NSRange]
    }
    public static let padTop: CGFloat = 12, padBottom: CGFloat = 12
    public let columns: [Column]
    public let rowNumbers: [Int]
    /// Y superior de cada fila (incluido su relleno) y su altura total.
    public let rowTops: [CGFloat]
    public let rowHeights: [CGFloat]
    public let totalHeight: CGFloat

    /// Fila visible en la posición vertical `y`.
    public func row(atY y: CGFloat) -> Int? {
        guard !rowTops.isEmpty else { return nil }
        var lo = 0, hi = rowTops.count - 1, ans = 0
        while lo <= hi {
            let mid = (lo + hi) / 2
            if rowTops[mid] <= y { ans = mid; lo = mid + 1 } else { hi = mid - 1 }
        }
        return rowNumbers[ans]
    }

    /// Y de la fila `n` (o de la primera con número >= n).
    public func top(ofRow n: Int) -> CGFloat? {
        if let i = rowNumbers.firstIndex(where: { $0 >= n }) { return rowTops[i] }
        return rowTops.last
    }

    /// Filas tocadas por una selección (rangos por columna).
    public func rows(intersecting sel: [(column: Int, range: NSRange)]) -> Set<Int> {
        var out = Set<Int>()
        for s in sel where s.range.length > 0 && columns.indices.contains(s.column) {
            for (n, r) in columns[s.column].verseRanges where NSIntersectionRange(r, s.range).length > 0 { out.insert(n) }
        }
        return out
    }
}

public enum ColumnsAttributedBuilder {
    static func paragraph(lineSpacing: CGFloat, after: CGFloat) -> NSParagraphStyle {
        let p = NSMutableParagraphStyle()
        p.lineSpacing = lineSpacing
        p.paragraphSpacing = after
        p.lineBreakMode = .byWordWrapping
        return p
    }

    /// Texto de una celda (sin salto final). Atributo `.bibliaVerse` = número de fila.
    static func cell(_ c: ParallelCell, row: Int, latin: Bool, pt: CGFloat, pal: ReaderPalette, ps: NSParagraphStyle,
                     annotations: ChapterAnnotations = ChapterAnnotations(), shownNotes: inout Set<Int64>) -> NSAttributedString {
        let kern: CGFloat = latin ? 0 : pt * 0.02
        let out = NSMutableAttributedString()
        var endNumber = row
        if case .verse(let v) = c { endNumber = max(row, v.endNumber) }
        let ann = annotations.forDisplayVerse(number: row, end: endNumber)
        func number(_ label: String, color: NSColor) {
            if ann.isBookmarked { out.append(AnnotationOverlays.bookmarkFlag(verse: row, pt: pt, palette: pal, paragraph: ps)) }
            out.append(NSAttributedString(string: label + "\u{2009}", attributes: [
                .font: ReaderFonts.verseNumber(size: pt * 0.62), .foregroundColor: color, .baselineOffset: pt * 0.38,
                .paragraphStyle: ps, .bibliaVerse: row, .bibliaVerseNumber: true]))
        }
        func text(_ t: String, color: NSColor, size: CGFloat) {
            var a: [NSAttributedString.Key: Any] = [.font: ReaderFonts.reading(latin: latin, size: size), .foregroundColor: color,
                                                    .paragraphStyle: ps, .bibliaVerse: row]
            if kern != 0 { a[.kern] = kern }
            out.append(NSAttributedString(string: t, attributes: a))
        }
        switch c {
        case .verse(let v):
            number(v.label, color: pal.verseNumber)
            text(v.text.trimmingCharacters(in: .whitespacesAndNewlines), color: pal.textPrimary, size: pt)
            for n in AnnotationOverlays.newNotes(ann, shown: &shownNotes) {
                out.append(AnnotationOverlays.noteIcon(noteId: n.id, verse: row, pt: pt, palette: pal, paragraph: ps))
            }
        case .covered(let v):
            number("\(row)", color: pal.textMuted)
            text("↑ (\(v.label))", color: pal.textMuted, size: pt * 0.9)
        case .missing:
            number("\(row)", color: pal.textMuted)
            text("—", color: pal.textMuted, size: pt)
        }
        return out
    }

    public static func build(rows: [ParallelRow], columns: [(id: String, language: String)], palette pal: ReaderPalette,
                             fontScale: Double, innerWidth: CGFloat, annotations: ChapterAnnotations = ChapterAnnotations()) -> BuiltColumns {
        let pt = ReaderStyle.baseSize * CGFloat(fontScale)
        let storage = NSTextStorage(), lm = NSLayoutManager()
        let tc = NSTextContainer(containerSize: NSSize(width: max(40, innerWidth), height: CGFloat.greatestFiniteMagnitude))
        tc.lineFragmentPadding = 0
        storage.addLayoutManager(lm); lm.addTextContainer(tc)
        func measure(_ a: NSAttributedString) -> CGFloat {
            storage.setAttributedString(a)
            lm.ensureLayout(for: tc)
            return lm.usedRect(for: tc).height
        }
        func latin(_ ci: Int) -> Bool { columns[ci].language != "zh" }
        func spacing(_ ci: Int) -> CGFloat { pt * ((latin(ci) ? 1.55 : 1.85) - 1.2) }

        // 1) cada celda y su altura natural
        var cells: [[NSAttributedString]] = columns.indices.map { _ in [] }
        var heights: [[CGFloat]] = columns.indices.map { _ in [] }
        var shown = columns.indices.map { _ in Set<Int64>() }
        for r in rows {
            for ci in columns.indices {
                let c = r.cells[safe: ci] ?? .missing
                let a = cell(c, row: r.number, latin: latin(ci), pt: pt, pal: pal, ps: paragraph(lineSpacing: spacing(ci), after: 0),
                             annotations: annotations, shownNotes: &shown[ci])
                cells[ci].append(a)
                // usedRect no cuenta el interlineado de la última línea, pero el layout real sí lo suma antes del párrafo siguiente
                heights[ci].append(measure(a) + spacing(ci))
            }
        }
        // 2) altura de fila = la celda más alta; cada celda rellena el resto con espacio de párrafo
        var rowH: [CGFloat] = [], tops: [CGFloat] = []
        var y: CGFloat = 0
        for i in rows.indices {
            let h = columns.indices.map { heights[$0][i] }.max() ?? 0
            rowH.append(h + BuiltColumns.padTop + BuiltColumns.padBottom)
            tops.append(y)
            y += rowH[i]
        }
        var built: [BuiltColumns.Column] = []
        for ci in columns.indices {
            let out = NSMutableAttributedString()
            var ranges: [Int: NSRange] = [:]
            for (i, r) in rows.enumerated() {
                let extra = rowH[i] - heights[ci][i]   // el relleno de la fila va como espacio de párrafo
                let ps = paragraph(lineSpacing: spacing(ci), after: extra)
                let start = out.length
                let cellStr = NSMutableAttributedString(attributedString: cells[ci][i])
                cellStr.addAttribute(.paragraphStyle, value: ps, range: NSRange(location: 0, length: cellStr.length))
                out.append(cellStr)
                ranges[r.number] = NSRange(location: start, length: out.length - start)
                if i < rows.count - 1 {
                    out.append(NSAttributedString(string: "\n", attributes: [
                        .font: ReaderFonts.reading(latin: latin(ci), size: pt), .paragraphStyle: ps]))
                }
            }
            built.append(.init(id: columns[ci].id, language: columns[ci].language, text: out, verseRanges: ranges))
        }
        return BuiltColumns(columns: built, rowNumbers: rows.map(\.number), rowTops: tops, rowHeights: rowH, totalHeight: y)
    }
}

// MARK: - Principal + glosas

public enum GlossAttributedBuilder {
    /// Aviso (con enlace) cuando no hay glosas elegidas.
    public static func noGlossesNotice(style s: ReaderStyle) -> NSAttributedString {
        let pt = s.pt * 0.85
        let ps = NSMutableParagraphStyle(); ps.paragraphSpacing = s.pt * 0.9
        let out = NSMutableAttributedString(string: "Sin glosas: solo se lee la versión principal. ", attributes: [
            .font: NSFont.systemFont(ofSize: pt), .foregroundColor: s.palette.textMuted, .paragraphStyle: ps])
        out.append(NSAttributedString(string: "Elegir glosas", attributes: [
            .font: NSFont.systemFont(ofSize: pt), .foregroundColor: s.palette.accent, .paragraphStyle: ps,
            .link: "biblia://glosas", .underlineStyle: NSUnderlineStyle.single.rawValue]))
        out.append(NSAttributedString(string: "\n", attributes: [.font: NSFont.systemFont(ofSize: pt), .paragraphStyle: ps]))
        return out
    }

    /// Bloques planos (con ids consecutivos) y líneas de glosa tras el último bloque de cada versículo.
    public static func flatten(groups: [GlossGroup]) -> (blocks: [BookBlock], lastBlockId: [Int: Int]) {
        var blocks: [BookBlock] = []
        var last: [Int: Int] = [:]
        for g in groups {
            var bs = g.blocks
            if bs.isEmpty {   // la principal no tiene el versículo: hueco atenuado
                bs = [BookBlock(id: 0, kind: .prose, level: 1, headingKind: "", flush: true,
                                pieces: [Piece(verse: g.number, end: g.number, label: "\(g.number)", text: "\u{2014}")], anchorVerse: g.number)]
            }
            for b in bs {
                blocks.append(BookBlock(id: blocks.count, kind: b.kind, level: b.level, headingKind: b.headingKind, flush: b.flush,
                                        pieces: b.pieces, anchorVerse: b.anchorVerse))
            }
            last[g.number] = blocks.count - 1
        }
        return (blocks, last)
    }

    static func lines(_ g: GlossGroup, style s: ReaderStyle, tabLocation: CGFloat) -> BlockExtra? {
        guard !g.glosses.isEmpty else { return nil }
        let pal = s.palette
        let gp = s.pt * 0.82
        let indent = s.pt * 1.5
        let out = NSMutableAttributedString()
        for (i, gl) in g.glosses.enumerated() {
            let latin = gl.language != "zh"
            let ps = NSMutableParagraphStyle()
            ps.firstLineHeadIndent = indent
            ps.headIndent = tabLocation
            ps.tabStops = [NSTextTab(textAlignment: .left, location: tabLocation, options: [:])]
            ps.lineSpacing = gp * ((latin ? 1.5 : 1.8) - 1.2)
            ps.paragraphSpacingBefore = i == 0 ? s.pt * 0.1 : 0
            ps.paragraphSpacing = i == g.glosses.count - 1 ? s.pt * 0.3 : s.pt * 0.06
            ps.lineBreakMode = .byWordWrapping
            let base: [NSAttributedString.Key: Any] = [.paragraphStyle: ps, .bibliaVerse: g.number, .bibliaGloss: true]
            func add(_ t: String, _ extra: [NSAttributedString.Key: Any]) {
                out.append(NSAttributedString(string: t, attributes: base.merging(extra) { $1 }))
            }
            add(gl.translationId, [.font: NSFont.systemFont(ofSize: gp * 0.78, weight: .bold), .foregroundColor: pal.versionColor(gl.versionIndex), .kern: 0.5])
            add("\t", [.font: ReaderFonts.reading(latin: latin, size: gp)])
            let font = ReaderFonts.reading(latin: latin, size: gp)
            switch gl.content {
            case .text(let v):
                if v.endNumber > v.number { add(v.label + "\u{2009}", [.font: NSFont.systemFont(ofSize: gp * 0.8), .foregroundColor: pal.textMuted]) }
                add(v.text.trimmingCharacters(in: .whitespacesAndNewlines), [.font: font, .foregroundColor: pal.textSecondary])
            case .merged(let label):
                add("(\(label))", [.font: font, .foregroundColor: pal.textMuted])
            }
            add("\n", [.font: font])
        }
        return BlockExtra(text: out, verse: g.number, trailing: gp * 0.3)
    }

    public static func tabLocation(groups: [GlossGroup], style s: ReaderStyle) -> CGFloat {
        let gp = s.pt * 0.82
        var w: CGFloat = 0
        for g in groups { for gl in g.glosses {
            let a = NSAttributedString(string: gl.translationId, attributes: [.font: NSFont.systemFont(ofSize: gp * 0.78, weight: .bold), .kern: 0.5])
            w = max(w, a.size().width)
        } }
        return s.pt * 1.5 + ceil(w) + gp * 0.8
    }

    public static func build(title: String, groups: [GlossGroup], style s: ReaderStyle, notice: Bool = false) -> BuiltChapter {
        var st = s
        st.perVerse = false          // la poesía mantiene su interlineado; la prosa su separación habitual
        let flat = flatten(groups: groups)
        let tab = tabLocation(groups: groups, style: s)
        var extras: [Int: BlockExtra] = [:]
        for g in groups {
            if let id = flat.lastBlockId[g.number], let ex = lines(g, style: s, tabLocation: tab) { extras[id] = ex }
        }
        return ChapterAttributedBuilder.build(title: title, blocks: flat.blocks, style: st, extras: extras,
                                              afterTitle: notice ? noGlossesNotice(style: s) : nil)
    }
}
