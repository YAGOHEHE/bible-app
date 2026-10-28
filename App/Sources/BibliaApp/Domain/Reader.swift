import Foundation

/// Un versículo listo para mostrar. Si la versión fusiona versículos (CUV Num 1:20 = 20–21),
/// `endNumber > number` y la etiqueta es "20–21".
struct DisplayVerse: Identifiable, Hashable {
    let number: Int
    let endNumber: Int
    let text: String
    var headings: [String]
    /// Jerarquía de cada título, en paralelo a `headings`: ms | s1 | s2 | d | r.
    var headingKinds: [String] = []
    var id: Int { number }
    var label: String { endNumber > number ? "\(number)–\(endNumber)" : "\(number)" }
}

enum ChapterBuilder {
    /// - Parameter referenceMax: último versículo del capítulo en una versión de referencia (KJV);
    ///   permite etiquetar una fusión al final del capítulo.
    static func build(verses: [Verse], headings: [Heading], referenceMax: Int? = nil) -> [DisplayVerse] {
        // (ver también `blocks`)
        let vs = verses.sorted { $0.verse < $1.verse }
        var out: [DisplayVerse] = []
        for (i, v) in vs.enumerated() {
            var end = v.verse
            if i + 1 < vs.count {
                if vs[i + 1].verse > v.verse + 1 { end = vs[i + 1].verse - 1 }
            } else if let m = referenceMax, m > v.verse {
                end = m
            }
            out.append(DisplayVerse(number: v.verse, endNumber: end, text: v.text, headings: []))
        }
        guard !out.isEmpty else { return out }
        // Títulos: al versículo que los contiene (o al siguiente presente); orden de entrada (rowid).
        for h in headings {
            let idx = out.firstIndex { $0.endNumber >= h.verse } ?? out.count - 1
            out[idx].headings.append(h.text)
            out[idx].headingKinds.append(h.kind ?? "s1")
        }
        return out
    }
}

struct ChapterPosition: Equatable, Hashable {
    var book: Int
    var chapter: Int
}

/// Navegación entre capítulos con fronteras de libro. `counts[book-1]` = nº de capítulos.
struct ChapterNav {
    let counts: [Int]

    func next(_ p: ChapterPosition) -> ChapterPosition? {
        guard (1...counts.count).contains(p.book) else { return nil }
        if p.chapter < counts[p.book - 1] { return ChapterPosition(book: p.book, chapter: p.chapter + 1) }
        var b = p.book + 1
        while b <= counts.count {
            if counts[b - 1] > 0 { return ChapterPosition(book: b, chapter: 1) }
            b += 1
        }
        return nil
    }

    func prev(_ p: ChapterPosition) -> ChapterPosition? {
        guard (1...counts.count).contains(p.book) else { return nil }
        if p.chapter > 1 { return ChapterPosition(book: p.book, chapter: p.chapter - 1) }
        var b = p.book - 1
        while b >= 1 {
            if counts[b - 1] > 0 { return ChapterPosition(book: b, chapter: counts[b - 1]) }
            b -= 1
        }
        return nil
    }
}

enum CopyFormatter {
    /// `“texto” — Juan 3:16 (RV1909)`. Versículos contiguos se agrupan: `Juan 3:16–18`.
    static func format(verses: [DisplayVerse], bookName: String, chapter: Int,
                       translationId: String, language: String) -> String {
        let vs = verses.sorted { $0.number < $1.number }
        guard !vs.isEmpty else { return "" }
        let joiner = language == "zh" ? "" : " "
        let text = vs.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }.joined(separator: joiner)
        var parts: [String] = []
        var start = vs[0].number, end = vs[0].endNumber
        for v in vs.dropFirst() {
            if v.number == end + 1 { end = v.endNumber } else {
                parts.append(start == end ? "\(start)" : "\(start)–\(end)")
                start = v.number; end = v.endNumber
            }
        }
        parts.append(start == end ? "\(start)" : "\(start)–\(end)")
        return "“\(text)” — \(bookName) \(chapter):\(parts.joined(separator: ", ")) (\(translationId))"
    }
}

/// Posición de lectura persistida (F01).
struct ResumeState: Equatable {
    var translation: String
    var book: Int
    var chapter: Int
    var verse: Int

    private static let key = "resume.state"

    func save(to d: UserDefaults = .standard) {
        d.set(["t": translation, "b": book, "c": chapter, "v": verse] as [String: Any], forKey: Self.key)
    }

    static func load(from d: UserDefaults = .standard) -> ResumeState? {
        guard let m = d.dictionary(forKey: key), let t = m["t"] as? String, let b = m["b"] as? Int,
              let c = m["c"] as? Int, let v = m["v"] as? Int, (1...66).contains(b), c >= 1 else { return nil }
        return ResumeState(translation: t, book: b, chapter: c, verse: max(1, v))
    }

    static func loadRecents(from d: UserDefaults = .standard) -> [Int] {
        (d.array(forKey: "recent.books") as? [Int] ?? []).filter { (1...66).contains($0) }
    }
    static func saveRecents(_ r: [Int], to d: UserDefaults = .standard) { d.set(r, forKey: "recent.books") }

    static func pushRecent(_ book: Int, into list: [Int], max m: Int = 8) -> [Int] {
        Array(([book] + list.filter { $0 != book }).prefix(m))
    }
}

/// Trozo de un versículo dentro de un bloque. `label` solo en la primera aparición del versículo
/// en el capítulo (el número en superíndice); `end` > `verse` si la versión fusiona versículos.
struct Piece: Hashable {
    let verse: Int
    let end: Int
    let label: String?
    let text: String
}

/// Bloque de maquetación: título, párrafo, línea de poesía, elemento de lista o línea en blanco.
/// `id` = posición en el capítulo; se usa como ancla de desplazamiento.
struct BookBlock: Identifiable, Equatable {
    enum Kind: Equatable { case heading, prose, poetry, list, blank }
    let id: Int
    let kind: Kind
    /// Nivel de sangría (poesía/listas) o, en títulos, irrelevante.
    let level: Int
    /// ms | s1 | s2 | d | r (solo títulos)
    let headingKind: String
    /// `m`: párrafo sin sangría (continuación tras poesía o cita).
    let flush: Bool
    let pieces: [Piece]
    /// Versículo al que ancla el bloque (en títulos, el que precede).
    let anchorVerse: Int

    func contains(_ v: Int) -> Bool { kind != .heading && pieces.contains { $0.verse <= v && v <= $0.end } }
    var verseNumbers: Set<Int> { Set(pieces.map(\.verse)) }
}

extension ChapterBuilder {
    enum Mode { case book, perVerse }

    /// Bloques del capítulo. `.book` usa la tabla `layout`; sin ella (o en `.perVerse`) cada
    /// versículo es su propio párrafo. Respeta versículos fusionados y títulos de versículos ausentes
    /// (ya resueltos en `items`).
    static func blocks(items: [DisplayVerse], layout: [LayoutPiece], mode: Mode, showHeadings: Bool) -> [BookBlock] {
        var out: [BookBlock] = []
        func add(_ kind: BookBlock.Kind, level: Int = 1, hk: String = "", flush: Bool = false, pieces: [Piece], anchor: Int) {
            out.append(BookBlock(id: out.count, kind: kind, level: level, headingKind: hk, flush: flush, pieces: pieces, anchorVerse: anchor))
        }
        func addHeadings(_ v: DisplayVerse) {
            guard showHeadings else { return }
            for (i, h) in v.headings.enumerated() {
                add(.heading, hk: v.headingKinds[safe: i] ?? "s1", pieces: [Piece(verse: v.number, end: v.number, label: nil, text: h)], anchor: v.number)
            }
        }
        let byNumber = Dictionary(uniqueKeysWithValues: items.map { ($0.number, $0) })
        if mode == .perVerse || layout.isEmpty || items.isEmpty {
            for v in items {
                addHeadings(v)
                add(.prose, flush: true, pieces: [Piece(verse: v.number, end: v.endNumber, label: v.label, text: v.text)], anchor: v.number)
            }
            return out
        }
        var seen = Set<Int>()
        var cur: (kind: BookBlock.Kind, level: Int, flush: Bool, pieces: [Piece])?
        func flush() {
            if let c = cur, let f = c.pieces.first { add(c.kind, level: c.level, flush: c.flush, pieces: c.pieces, anchor: f.verse) }
            cur = nil
        }
        var lastKind: BookBlock.Kind = .prose
        for lp in layout {
            if lp.kind == "b" {
                flush()
                if let last = out.last, last.kind != .blank { add(.blank, pieces: [], anchor: last.anchorVerse) }
                continue
            }
            guard let v = byNumber[lp.verse] else { continue }
            let first = !seen.contains(v.number)
            let piece = Piece(verse: v.number, end: v.endNumber, label: first ? v.label : nil, text: lp.text)
            let opens = lp.kind != "+"
            var kind: BookBlock.Kind { switch lp.kind {
                case "q", "qr": return .poetry
                case "li": return .list
                case "+": return lastKind
                default: return .prose } }
            if first && !v.headings.isEmpty && showHeadings {
                flush(); addHeadings(v)
                // el trozo que sigue a un título abre bloque aunque fuera continuación
                cur = (kind, lp.level, lp.kind == "m", [piece])
                lastKind = kind
            } else if opens || cur == nil {
                flush()
                cur = (kind, lp.level, lp.kind == "m" || lp.kind == "pmo", [piece])
                lastKind = kind
            } else {
                cur?.pieces.append(piece)
            }
            seen.insert(v.number)
        }
        flush()
        // versículos sin trozos de maquetación (datos incompletos): no se pierden
        for v in items where !seen.contains(v.number) {
            add(.prose, flush: true, pieces: [Piece(verse: v.number, end: v.endNumber, label: v.label, text: v.text)], anchor: v.number)
        }
        return out
    }

    /// Bloque al que desplazarse para ver `verse` (incluye los títulos que lo preceden).
    static func blockID(for verse: Int, in blocks: [BookBlock]) -> Int? {
        guard var i = blocks.firstIndex(where: { $0.contains(verse) }) else { return nil }
        while i > 0, blocks[i - 1].kind == .heading { i -= 1 }
        return blocks[i].id
    }
}
