import Foundation

/// Lógica pura de búsqueda y de "ir a referencia" (sin E/S, testeable).

// MARK: - consulta

public enum SearchTerms {
    /// "a/b" = OR. Separa por "/", recorta y descarta vacíos.
    public static func split(_ query: String) -> [String] {
        query.split(separator: "/").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }
}

// MARK: - resaltado

public enum SearchHighlighter {
    /// Rangos (no solapados, en orden) de todas las apariciones de cualquier término.
    /// Sin límites de palabra: vale para chino (carácter a carácter) y para latín (subcadena, como el índice trigram).
    /// Distingue acentos (como FTS5 trigram) pero no mayúsculas.
    public static func ranges(in text: String, terms: [String]) -> [Range<String.Index>] {
        var found: [Range<String.Index>] = []
        for t in terms where !t.isEmpty {
            var from = text.startIndex
            while from < text.endIndex, let r = text.range(of: t, options: [.caseInsensitive], range: from..<text.endIndex) {
                found.append(r)
                from = r.upperBound
            }
        }
        found.sort { $0.lowerBound < $1.lowerBound }
        var merged: [Range<String.Index>] = []
        for r in found {
            if let last = merged.last, r.lowerBound < last.upperBound {
                if r.upperBound > last.upperBound { merged[merged.count - 1] = last.lowerBound..<r.upperBound }
            } else {
                merged.append(r)
            }
        }
        return merged
    }

    /// Versículo recortado alrededor de la primera coincidencia (para filas de resultados).
    public static func window(_ text: String, terms: [String], maxLength: Int = 150, lead: Int = 36) -> String {
        guard text.count > maxLength, let first = ranges(in: text, terms: terms).first else { return text }
        let startOffset = max(0, text.distance(from: text.startIndex, to: first.lowerBound) - lead)
        let start = text.index(text.startIndex, offsetBy: startOffset)
        let end = text.index(start, offsetBy: min(maxLength, text.distance(from: start, to: text.endIndex)))
        return (startOffset > 0 ? "…" : "") + text[start..<end] + (end < text.endIndex ? "…" : "")
    }
}

// MARK: - agrupación

public struct SearchGroup: Identifiable, Equatable {
    public init(book: Int, count: Int, hits: [SearchHit]) { self.book = book; self.count = count; self.hits = hits }
    public let book: Int
    public let count: Int          // coincidencias totales del libro (no solo las cargadas)
    public let hits: [SearchHit]
    public var id: Int { book }
}

public enum SearchGrouping {
    /// Agrupa por libro conservando el orden canónico; `totals` aporta el recuento real por libro.
    public static func group(_ hits: [SearchHit], totals: [Int: Int] = [:]) -> [SearchGroup] {
        var order: [Int] = []
        var by: [Int: [SearchHit]] = [:]
        for h in hits {
            if by[h.book] == nil { order.append(h.book) }
            by[h.book, default: []].append(h)
        }
        return order.sorted().map { SearchGroup(book: $0, count: totals[$0] ?? by[$0]!.count, hits: by[$0]!) }
    }
}

// MARK: - ir a referencia

public enum GotoFailure: Error, Equatable {
    case notReference
    case chapterOutOfRange(book: Int, max: Int)
    case verseOutOfRange(max: Int)
}

public enum GotoResolver {
    public static let examples = "Juan 3:16, 约3:16, John 3:16"

    /// Normaliza formas chinas habituales: "约翰福音3章16节" -> "约翰福音3:16", "诗篇23篇" -> "诗篇23".
    public static func normalize(_ text: String) -> String {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "第", with: "")
            .replacingOccurrences(of: "章", with: ":")
            .replacingOccurrences(of: "节", with: "").replacingOccurrences(of: "節", with: "")
        if s.hasSuffix(":") { s.removeLast() }
        if s.hasSuffix("篇"), let l = s.dropLast().last, l.isNumber { s.removeLast() }
        return s
    }

    /// Texto -> referencia validada contra el número de capítulos (`counts[book-1]`).
    /// Acepta "Juan 3:16", "Rom 8:28-39", "Salmos 23" y un nombre de libro solo ("Juan" = capítulo 1).
    public static func resolve(_ text: String, chapterCounts counts: [Int]) -> Result<BibleRef, GotoFailure> {
        let s = normalize(text)
        guard !s.isEmpty else { return .failure(.notReference) }
        var ref: BibleRef
        do {
            ref = try ReferenceParser.parse(s)
        } catch ReferenceError.zeroChapter(let b) {
            return .failure(.chapterOutOfRange(book: b, max: counts[safe: b - 1] ?? 0))
        } catch {
            guard let b = try? ReferenceParser.resolveBook(s) else { return .failure(.notReference) }
            ref = BibleRef(book: b, chapter: 1, verseFrom: nil, verseTo: nil)
        }
        guard (1...66).contains(ref.book) else { return .failure(.notReference) }
        let maxC = counts[safe: ref.book - 1] ?? 0
        guard ref.chapter >= 1, ref.chapter <= maxC else {
            return .failure(.chapterOutOfRange(book: ref.book, max: maxC))
        }
        if let a = ref.verseFrom {
            guard a >= 1 else { return .failure(.notReference) }
            let b = ref.verseTo ?? a
            ref.verseFrom = min(a, b); ref.verseTo = max(a, b)
        }
        return .success(ref)
    }
}

// MARK: - sugerencia de otra versión (BUG-005)

public struct SearchSuggestion: Equatable {
    public init(translationId: String, count: Int) { self.translationId = translationId; self.count = count }
    public var translationId: String
    public var count: Int

    /// Versión con más coincidencias entre las demás (empate: la primera). `nil` si ninguna tiene.
    public static func best(counts: [(id: String, count: Int)], excluding current: String) -> SearchSuggestion? {
        var best: SearchSuggestion?
        for c in counts where c.id != current && c.count > 0 {
            if best == nil || c.count > best!.count { best = SearchSuggestion(translationId: c.id, count: c.count) }
        }
        return best
    }

    public func message(query: String, current: String) -> String {
        "Sin resultados en \(current). «\(query)» aparece \(count) \(count == 1 ? "vez" : "veces") en \(translationId)"
    }
}

/// Nombre de libro según el idioma de la versión (BUG-006): KJV -> inglés, CUV -> chino, RV1909 -> español.
public enum BookNameLanguage {
    public static func name(_ n: Int, language: String) -> String {
        guard let b = ReferenceParser.books[safe: n - 1] else { return "\(n)" }
        switch language {
        case "en": return b.1
        case "zh": return b.3
        case "zh-Hant": return ReferenceParser.traditional[safe: n - 1]?.0 ?? b.3
        default: return b.2
        }
    }

    /// Idioma de `book_names` para una versión: CUVT usa chino tradicional (BUG-V11-03); el resto, su idioma.
    public static func forTranslation(id: String, language: String) -> String {
        id == "CUVT" ? "zh-Hant" : language
    }
}
