import Foundation

public struct CrossRefRow: Identifiable, Hashable {
    public init(target: BibleRef, label: String, snippet: String? = nil, votes: Int) { self.target = target; self.label = label; self.snippet = snippet; self.votes = votes }
    public var target: BibleRef
    public var label: String
    /// `nil` = el versículo no existe en esta versión (numeración distinta): se muestra «—».
    public var snippet: String?
    public var votes: Int
    public var id: String { "\(target.book)-\(target.chapter)-\(target.verseFrom ?? 0)-\(target.verseTo ?? 0)" }
}

public enum CrossRefList {
    public static let pageSize = 100

    /// Une las referencias de varios versículos de origen: sin duplicados (por destino, con los votos más altos),
    /// de más a menos votadas y, a igual voto, en orden bíblico.
    public static func merge(_ lists: [[CrossRef]]) -> [CrossRef] {
        var best: [BibleRef: CrossRef] = [:]
        for r in lists.flatMap({ $0 }) {
            if let old = best[r.target], old.votes >= r.votes { continue }
            best[r.target] = r
        }
        return best.values.sorted {
            if $0.votes != $1.votes { return $0.votes > $1.votes }
            return ($0.toBook, $0.toChapter, $0.toVerseStart) < ($1.toBook, $1.toChapter, $1.toVerseStart)
        }
    }

    /// Une los versículos presentes (chino sin espacios); `nil` si no hay ninguno.
    public static func join(_ texts: [String], language: String) -> String? {
        let ts = texts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        return ts.isEmpty ? nil : ts.joined(separator: language == "zh" ? "" : " ")
    }

    public static func row(_ r: CrossRef, bookName: (Int) -> String, text: (BibleRef) -> String?) -> CrossRefRow {
        CrossRefRow(target: r.target, label: RefLabel.text(bookName: bookName(r.toBook), ref: r.target),
                    snippet: text(r.target), votes: r.votes)
    }
}
