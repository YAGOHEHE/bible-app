import Foundation

enum ParallelLayout: String, CaseIterable, Identifiable {
    case columns, interleaved
    var id: String { rawValue }
    var label: String { self == .columns ? "Columnas" : "Intercalado" }
}

/// Reglas de versificación: una laguna en la numeración es una FUSIÓN (el versículo anterior
/// contiene también el ausente) o una OMISIÓN (el versículo no existe en esa versión).
enum Versification {
    /// Versiones cuyo texto fusiona versículos consecutivos (CUV: Núm 1:20 = 20–21).
    static let mergingTranslations: Set<String> = ["CUV"]
    /// Versículos del NT omitidos (no fusionados) por criterio textual: libro·capítulo·versículo.
    static let ntOmissions: Set<[Int]> = [
        [40, 18, 11], [40, 23, 14], [41, 7, 16], [41, 15, 28], [42, 17, 36], [42, 23, 17],
        [43, 5, 4], [43, 7, 53], [44, 8, 37], [44, 15, 34], [44, 24, 7], [44, 28, 29],
    ]

    static func gapIsMerge(translationId: String, book: Int, chapter: Int, verse: Int) -> Bool {
        guard mergingTranslations.contains(translationId) else { return false }
        return !(book >= 40 && ntOmissions.contains([book, chapter, verse]))
    }
}

enum ParallelCell: Equatable {
    case verse(DisplayVerse)
    /// El versículo está cubierto por el rango fusionado de uno anterior.
    case covered(by: DisplayVerse)
    case missing
}

struct ParallelRow: Identifiable, Equatable {
    let number: Int
    let cells: [ParallelCell]
    var id: Int { number }
}

struct ParallelColumnData {
    var translationId: String
    var language: String
    var items: [DisplayVerse]
}

enum ParallelBuilder {
    /// Alinea por número de versículo sobre la unión de números de todas las columnas.
    static func build(book: Int, chapter: Int, columns: [ParallelColumnData]) -> [ParallelRow] {
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

enum ParallelCopy {
    /// Una línea por versión visible, con la referencia en el idioma de cada versión.
    static func format(rows: [ParallelRow], selected: Set<Int>, book: Int, chapter: Int,
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
            lines.append(CopyFormatter.format(verses: vs, bookName: bookName(book, col.language), chapter: chapter,
                                              translationId: col.id, language: col.language))
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }
}

/// Conjunto de versiones para la vista paralela (S04): orden, activadas. Persistente.
struct VersionSet: Equatable {
    static let maxColumns = 3
    var order: [String]
    var enabled: Set<String>

    /// Columnas paralelas: la principal primero, luego las activadas según el orden elegido.
    func columns(primary: String) -> [String] {
        let rest = order.filter { enabled.contains($0) && $0 != primary }
        return Array(([primary] + rest).prefix(Self.maxColumns))
    }

    /// Activadas efectivas (incluida la principal), sin recorte a 3.
    func enabledCount(primary: String) -> Int {
        Set(enabled).union([primary]).intersection(order).count
    }

    mutating func reconcile(installed: [String], primary: String) {
        order = order.filter { installed.contains($0) } + installed.filter { !order.contains($0) }
        enabled = enabled.filter { installed.contains($0) }
        if installed.contains(primary) { enabled.insert(primary) }
        if enabled.count < 2, let other = order.first(where: { !enabled.contains($0) }) { enabled.insert(other) }
    }

    private static let orderKey = "par.order", enabledKey = "par.enabled"

    func save(to d: UserDefaults = .standard) {
        d.set(order, forKey: Self.orderKey)
        d.set(order.filter { enabled.contains($0) }, forKey: Self.enabledKey)
    }

    static func load(from d: UserDefaults = .standard, installed: [String], primary: String) -> VersionSet {
        var s = VersionSet(order: d.stringArray(forKey: orderKey) ?? [],
                           enabled: Set(d.stringArray(forKey: enabledKey) ?? []))
        s.reconcile(installed: installed, primary: primary)
        return s
    }
}
