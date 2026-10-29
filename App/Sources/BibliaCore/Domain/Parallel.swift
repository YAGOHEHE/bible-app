import Foundation

public enum ParallelLayout: String, CaseIterable, Identifiable {
    case columns, interleaved
    public var id: String { rawValue }
    public var label: String { self == .columns ? "Columnas" : "Intercalado" }
}

/// Reglas de versificación: una laguna en la numeración es una FUSIÓN (el versículo anterior
/// contiene también el ausente) o una OMISIÓN (el versículo no existe en esa versión).
public enum Versification {
    /// Versiones cuyo texto fusiona versículos consecutivos (CUV: Núm 1:20 = 20–21).
    public static let mergingTranslations: Set<String> = ["CUV"]
    /// Versículos del NT omitidos (no fusionados) por criterio textual: libro·capítulo·versículo.
    public static let ntOmissions: Set<[Int]> = [
        [40, 18, 11], [40, 23, 14], [41, 7, 16], [41, 15, 28], [42, 17, 36], [42, 23, 17],
        [43, 5, 4], [43, 7, 53], [44, 8, 37], [44, 15, 34], [44, 24, 7], [44, 28, 29],
    ]

    public static func gapIsMerge(translationId: String, book: Int, chapter: Int, verse: Int) -> Bool {
        guard mergingTranslations.contains(translationId) else { return false }
        return !(book >= 40 && ntOmissions.contains([book, chapter, verse]))
    }
}

public enum ParallelCell: Equatable {
    case verse(DisplayVerse)
    /// El versículo está cubierto por el rango fusionado de uno anterior.
    case covered(by: DisplayVerse)
    case missing
}

public struct ParallelRow: Identifiable, Equatable {
    public init(number: Int, cells: [ParallelCell]) { self.number = number; self.cells = cells }
    public let number: Int
    public let cells: [ParallelCell]
    public var id: Int { number }
}

public struct ParallelColumnData {
    public init(translationId: String, language: String, items: [DisplayVerse]) { self.translationId = translationId; self.language = language; self.items = items }
    public var translationId: String
    public var language: String
    public var items: [DisplayVerse]
}

public enum ParallelBuilder {
    /// Alinea por número de versículo sobre la unión de números de todas las columnas.
    public static func build(book: Int, chapter: Int, columns: [ParallelColumnData]) -> [ParallelRow] {
        // Cada versículo con su fin efectivo (solo cuenta como rango lo que es fusión real).
        let adjusted: [[DisplayVerse]] = columns.map { col in
            col.items.map { v in
                var e = v.number
                while e < v.endNumber,
                      Versification.gapIsMerge(translationId: col.translationId, book: book, chapter: chapter, verse: e + 1) {
                    e += 1
                }
                return DisplayVerse(number: v.number, endNumber: e, text: v.text, headings: v.headings)
            }
        }
        let numbers = Set(adjusted.flatMap { $0.map(\.number) }).sorted()
        return numbers.map { n in
            ParallelRow(number: n, cells: adjusted.map { items in
                if let v = items.first(where: { $0.number == n }) { return .verse(v) }
                if let v = items.first(where: { $0.number < n && n <= $0.endNumber }) { return .covered(by: v) }
                return .missing
            })
        }
    }
}

public enum ParallelCopy {
    /// Una línea por versión visible, con la referencia en el idioma de cada versión.
    public static func format(rows: [ParallelRow], selected: Set<Int>, book: Int, chapter: Int,
                       columns: [(id: String, language: String)],
                       bookName: (Int, String) -> String) -> String? {
        let chosen = rows.filter { selected.contains($0.number) }
        guard !chosen.isEmpty else { return nil }
        var lines: [String] = []
        for (i, col) in columns.enumerated() {
            var seen = Set<Int>()
            var vs: [DisplayVerse] = []
            for r in chosen {
                guard let cell = r.cells[safe: i] else { continue }
                switch cell {
                case .verse(let v), .covered(let v):
                    if seen.insert(v.number).inserted { vs.append(v) }
                case .missing: break
                }
            }
            guard !vs.isEmpty else { continue }
            lines.append(CopyFormatter.format(verses: vs, bookName: bookName(book, BookNameLanguage.forTranslation(id: col.id, language: col.language)), chapter: chapter,
                                              translationId: col.id, language: col.language))
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }
}

/// Conjunto de versiones para la vista paralela (S04): orden, activadas. Persistente.
public struct VersionSet: Equatable {
    public init(order: [String], enabled: Set<String>) { self.order = order; self.enabled = enabled }
    public static let maxColumns = 3
    public var order: [String]
    public var enabled: Set<String>

    /// Columnas paralelas: la principal primero, luego las activadas según el orden elegido.
    public func columns(primary: String) -> [String] {
        let rest = order.filter { enabled.contains($0) && $0 != primary }
        return Array(([primary] + rest).prefix(Self.maxColumns))
    }

    /// Activadas efectivas (incluida la principal), sin recorte a 3.
    public func enabledCount(primary: String) -> Int {
        Set(enabled).union([primary]).intersection(order).count
    }

    public mutating func reconcile(installed: [String], primary: String) {
        order = order.filter { installed.contains($0) } + installed.filter { !order.contains($0) }
        enabled = enabled.filter { installed.contains($0) }
        if installed.contains(primary) { enabled.insert(primary) }
        if enabled.count < 2, let other = order.first(where: { !enabled.contains($0) }) { enabled.insert(other) }
    }

    private static let orderKey = "par.order", enabledKey = "par.enabled"

    public func save(to d: UserDefaults = .standard) {
        d.set(order, forKey: Self.orderKey)
        d.set(order.filter { enabled.contains($0) }, forKey: Self.enabledKey)
    }

    public static func load(from d: UserDefaults = .standard, installed: [String], primary: String) -> VersionSet {
        var s = VersionSet(order: d.stringArray(forKey: orderKey) ?? [],
                           enabled: Set(d.stringArray(forKey: enabledKey) ?? []))
        s.reconcile(installed: installed, primary: primary)
        return s
    }
}

// MARK: - Glosas («Principal + glosas»)

/// Versiones elegidas como glosas del modo intercalado: máx. 3, sin la principal, en orden de elección.
/// Persistente aparte del conjunto de columnas (`par.glosses`).
public struct GlossSet: Equatable {
    public init(ids: [String] = []) { self.ids = ids }
    public static let maxGlosses = 3
    public var ids: [String] = []

    /// Glosas efectivas: sin la principal, sin duplicados, solo instaladas, máx. 3.
    public func effective(primary: String, installed: [String]? = nil) -> [String] {
        var seen = Set<String>(); var out: [String] = []
        for id in ids where id != primary && (installed?.contains(id) ?? true) && seen.insert(id).inserted { out.append(id) }
        return Array(out.prefix(Self.maxGlosses))
    }

    public func contains(_ id: String) -> Bool { ids.contains(id) }

    /// Marca/desmarca. Devuelve false si no cabe (ya hay 3) o es la principal.
    @discardableResult
    public mutating func toggle(_ id: String, primary: String) -> Bool {
        guard id != primary else { return false }
        if let i = ids.firstIndex(of: id) { ids.remove(at: i); return true }
        guard effective(primary: primary).count < Self.maxGlosses else { return false }
        ids.append(id)
        return true
    }

    public func canAdd(_ id: String, primary: String) -> Bool {
        id != primary && (contains(id) || effective(primary: primary).count < Self.maxGlosses)
    }

    /// Versiones candidatas (sin la principal) agrupadas por idioma en el orden 中文 / Español / English.
    public static func grouped(_ translations: [Translation], primary: String) -> [(language: String, items: [Translation])] {
        let rank = ["zh": 0, "es": 1, "en": 2]
        let langs = Set(translations.map(\.language)).sorted { (rank[$0] ?? 9, $0) < (rank[$1] ?? 9, $1) }
        return langs.compactMap { l in
            let items = translations.filter { $0.language == l && $0.id != primary }
            return items.isEmpty ? nil : (l, items)
        }
    }

    private static let key = "par.glosses", onKey = "par.glossesOn"
    public func save(to d: UserDefaults = .standard) { d.set(ids, forKey: Self.key) }
    public static func load(from d: UserDefaults = .standard) -> GlossSet { GlossSet(ids: d.stringArray(forKey: key) ?? []) }
    public static func loadVisible(from d: UserDefaults = .standard) -> Bool {
        d.object(forKey: onKey) == nil ? true : d.bool(forKey: onKey)
    }
    public static func saveVisible(_ v: Bool, to d: UserDefaults = .standard) { d.set(v, forKey: onKey) }
}

/// Una línea de glosa bajo un versículo.
public struct GlossLine: Equatable, Identifiable {
    public init(versionIndex: Int, translationId: String, language: String, content: Content) { self.versionIndex = versionIndex; self.translationId = translationId; self.language = language; self.content = content }
    public enum Content: Equatable { case text(DisplayVerse), merged(String) }
    public let versionIndex: Int          // posición de la versión en la lista (0 = principal)
    public let translationId: String
    public let language: String
    public let content: Content
    public var id: String { translationId }
}

/// Un versículo en el modo glosas: bloques de la principal (títulos, poesía…) + líneas de glosa.
public struct GlossGroup: Identifiable, Equatable {
    public init(number: Int, blocks: [BookBlock], glosses: [GlossLine], primaryMissing: Bool, primaryCovered: Bool) { self.number = number; self.blocks = blocks; self.glosses = glosses; self.primaryMissing = primaryMissing; self.primaryCovered = primaryCovered }
    public let number: Int
    public var blocks: [BookBlock]
    public var glosses: [GlossLine]
    /// La principal no tiene este versículo (omitido): se muestra un hueco atenuado.
    public var primaryMissing: Bool
    /// El versículo está cubierto por un rango fusionado de la principal (sus glosas siguen al bloque).
    public var primaryCovered: Bool
    public var id: Int { number }
}

public enum GlossBuilder {
    /// Reparte los bloques de la principal por versículo (un bloque por versículo; las líneas de poesía se
    /// conservan) y añade bajo cada uno las glosas presentes. `columns` = [principal] + glosas, igual que `rows.cells`.
    public static func groups(rows: [ParallelRow], blocks: [BookBlock], columns: [(id: String, language: String)],
                       showGlosses: Bool = true) -> [GlossGroup] {
        var perRow: [Int: [BookBlock]] = [:]
        var counter = 0
        func put(_ b: BookBlock, _ verse: Int) {
            let nb = BookBlock(id: counter, kind: b.kind, level: b.level, headingKind: b.headingKind, flush: b.flush,
                               pieces: b.pieces, anchorVerse: b.anchorVerse)
            counter += 1
            let key = rows.contains(where: { $0.number == verse }) ? verse
                : (rows.last { $0.number <= verse }?.number ?? rows.first?.number ?? verse)
            perRow[key, default: []].append(nb)
        }
        for b in blocks {
            switch b.kind {
            case .blank: continue
            case .heading: put(b, b.pieces.first?.verse ?? b.anchorVerse)
            default:
                // trocear por versículo consecutivo
                var run: [Piece] = []
                func flush() {
                    guard let f = run.first else { return }
                    put(BookBlock(id: 0, kind: b.kind, level: b.level, headingKind: b.headingKind, flush: b.flush || run.count < b.pieces.count,
                                  pieces: run, anchorVerse: f.verse), f.verse)
                    run = []
                }
                for p in b.pieces {
                    if let l = run.last, l.verse != p.verse { flush() }
                    run.append(p)
                }
                flush()
            }
        }
        var out: [GlossGroup] = []
        for row in rows {
            var lines: [GlossLine] = []
            if showGlosses {
                for (i, cell) in row.cells.enumerated() where i > 0 {
                    guard let col = columns[safe: i] else { continue }
                    switch cell {
                    case .verse(let v): lines.append(GlossLine(versionIndex: i, translationId: col.id, language: col.language, content: .text(v)))
                    case .covered(let v): lines.append(GlossLine(versionIndex: i, translationId: col.id, language: col.language, content: .merged(v.label)))
                    case .missing: break
                    }
                }
            }
            let cell0 = row.cells.first
            let missing = cell0 == .missing
            var covered = false
            if case .covered? = cell0 { covered = true }
            let bl = perRow[row.number] ?? []
            if bl.isEmpty && lines.isEmpty { continue }
            out.append(GlossGroup(number: row.number, blocks: bl, glosses: lines, primaryMissing: missing && bl.isEmpty, primaryCovered: covered))
        }
        // ids consecutivos en orden de lectura (el bloque anterior = id - 1)
        var n = 0
        for gi in out.indices {
            out[gi].blocks = out[gi].blocks.map { b in
                defer { n += 1 }
                return BookBlock(id: n, kind: b.kind, level: b.level, headingKind: b.headingKind, flush: b.flush,
                                 pieces: b.pieces, anchorVerse: b.anchorVerse)
            }
        }
        return out
    }

    /// Copia en modo glosas: la principal + las glosas visibles (una línea por versión).
    public static func copyText(rows: [ParallelRow], selected: Set<Int>, book: Int, chapter: Int,
                         columns: [(id: String, language: String)], showGlosses: Bool,
                         bookName: (Int, String) -> String) -> String? {
        ParallelCopy.format(rows: rows, selected: selected, book: book, chapter: chapter,
                            columns: showGlosses ? columns : Array(columns.prefix(1)), bookName: bookName)
    }
}
