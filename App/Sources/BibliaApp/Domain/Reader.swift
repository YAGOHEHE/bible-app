import Foundation

/// Un versículo listo para mostrar. Si la versión fusiona versículos (CUV Num 1:20 = 20–21),
/// `endNumber > number` y la etiqueta es "20–21".
struct DisplayVerse: Identifiable, Hashable {
    let number: Int
    let endNumber: Int
    let text: String
    var headings: [String]
    var id: Int { number }
    var label: String { endNumber > number ? "\(number)–\(endNumber)" : "\(number)" }
}

enum ChapterBuilder {
    /// - Parameter referenceMax: último versículo del capítulo en una versión de referencia (KJV);
    ///   permite etiquetar una fusión al final del capítulo.
    static func build(verses: [Verse], headings: [Heading], referenceMax: Int? = nil) -> [DisplayVerse] {
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

/// Unidad de desplazamiento/anclaje del lector. `id` = primer versículo del bloque.
struct ReaderBlock: Identifiable, Equatable {
    let id: Int
    let headings: [String]
    let verses: [DisplayVerse]
    /// Continúa el párrafo anterior (sin hueco superior).
    let continuation: Bool
    func contains(_ verse: Int) -> Bool { verses.contains { $0.number <= verse && verse <= $0.endNumber } }
}

enum BlockBuilder {
    static let paragraphChunk = 8

    static func build(items: [DisplayVerse], paragraph: Bool, showHeadings: Bool) -> [ReaderBlock] {
        guard !items.isEmpty else { return [] }
        if !paragraph {
            return items.map { ReaderBlock(id: $0.number, headings: showHeadings ? $0.headings : [], verses: [$0], continuation: false) }
        }
        var blocks: [ReaderBlock] = []
        var cur: [DisplayVerse] = []
        var curHeads: [String] = []
        var cont = false
        func flush() {
            if let f = cur.first { blocks.append(ReaderBlock(id: f.number, headings: curHeads, verses: cur, continuation: cont)) }
            cur = []; curHeads = []
        }
        for v in items {
            let starts = showHeadings && !v.headings.isEmpty
            if starts { flush(); cont = false; curHeads = v.headings }
            else if cur.count >= paragraphChunk { flush(); cont = true }
            cur.append(v)
        }
        flush()
        return blocks
    }
}
