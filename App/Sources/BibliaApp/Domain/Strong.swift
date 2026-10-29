import Foundation

/// Palabra etiquetada con un número Strong, localizada en el texto mostrado del versículo.
/// `start`/`length` son desplazamientos en caracteres sobre el texto completo del versículo.
struct StrongSpan: Equatable, Hashable {
    var start: Int
    var length: Int
    var strong: String
    var word: String
    var end: Int { start + length }
}

/// Palabra seleccionada (la abierta en el inspector).
struct StrongSelection: Equatable, Hashable {
    var strong: String
    var verse: Int
    var start: Int
}

enum StrongLink {
    static let scheme = "strong"

    static func url(_ s: StrongSpan, verse: Int) -> URL? {
        URL(string: "strong://\(s.strong)?v=\(verse)&s=\(s.start)")
    }

    static func parse(_ url: URL) -> StrongSelection? {
        guard url.scheme == scheme, let id = url.host?.uppercased(), !id.isEmpty,
              let c = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let q = Dictionary(uniqueKeysWithValues: (c.queryItems ?? []).compactMap { i in i.value.map { (i.name, $0) } })
        guard let v = q["v"].flatMap(Int.init), let s = q["s"].flatMap(Int.init) else { return nil }
        return StrongSelection(strong: id, verse: v, start: s)
    }
}

enum StrongAligner {
    /// Alinea las palabras etiquetadas (en orden) con el texto del versículo. Las palabras no
    /// concatenan byte a byte al texto, así que se busca cada una en orden ignorando puntuación y
    /// mayúsculas, exigiendo límites de palabra. Una palabra que no aparece se salta sin romper el resto.
    /// Las palabras sin número (strong == nil) no producen tramo.
    static func align(text: String, words: [VerseWord]) -> [StrongSpan] {
        let chars = Array(text)
        // Texto normalizado: solo letras/dígitos en minúscula, con el índice original de cada uno.
        var norm: [Character] = []
        var origin: [Int] = []
        for (i, ch) in chars.enumerated() where ch.isLetter || ch.isNumber {
            for l in String(ch).lowercased() { norm.append(l); origin.append(i) }
        }
        func isWordChar(_ i: Int) -> Bool { chars.indices.contains(i) && (chars[i].isLetter || chars[i].isNumber) }

        var spans: [StrongSpan] = []
        var cursor = 0          // posición en `norm`
        for w in words.sorted(by: { $0.idx < $1.idx }) {
            let target = Array(w.word.lowercased().filter { $0.isLetter || $0.isNumber })
            guard !target.isEmpty, target.count <= norm.count - cursor else { continue }
            var found: Int?
            var p = cursor
            while p + target.count <= norm.count {
                if norm[p] == target[0], Array(norm[p..<(p + target.count)]) == target {
                    let first = origin[p], last = origin[p + target.count - 1]
                    // límites de palabra en el texto original
                    let startsWord = !isWordChar(first - 1)
                    let endsWord = !isWordChar(last + 1)
                    if startsWord && endsWord { found = p; break }
                }
                p += 1
            }
            guard let f = found else { continue }
            let first = origin[f], last = origin[f + target.count - 1]
            cursor = f + target.count
            if let s = w.strong, !s.isEmpty {
                spans.append(StrongSpan(start: first, length: last - first + 1, strong: s, word: w.word))
            }
        }
        return spans
    }

    /// Tramos por versículo de un capítulo.
    static func alignChapter(verses: [Verse], words: [VerseWord]) -> [Int: [StrongSpan]] {
        let byVerse = Dictionary(grouping: words, by: \.verse)
        var out: [Int: [StrongSpan]] = [:]
        for v in verses {
            if let ws = byVerse[v.verse] {
                let s = align(text: v.text, words: ws)
                if !s.isEmpty { out[v.verse] = s }
            }
        }
        return out
    }
}

/// Apariciones de un número Strong (versículo + texto).
struct StrongOccurrence: Identifiable, Equatable {
    var ref: BibleRef
    var text: String
    var id: String { "\(ref.book)-\(ref.chapter)-\(ref.verseFrom ?? 0)" }
}

/// Historial agrupado por día (S07).
struct HistoryDay: Identifiable, Equatable {
    var title: String
    var day: Date
    var entries: [HistoryEntry]
    var id: Date { day }
}

enum HistoryGrouping {
    /// Misma versión + capítulo + versículo que la entrada retenida anterior (más reciente).
    static func isSame(_ a: HistoryEntry, _ b: HistoryEntry) -> Bool {
        a.translationId == b.translationId && a.book == b.book && a.chapter == b.chapter && a.verse == b.verse
    }

    /// Elimina entradas consecutivas iguales (conserva la más reciente). Entrada: más reciente primero.
    static func dedupe(_ entries: [HistoryEntry]) -> [HistoryEntry] {
        var out: [HistoryEntry] = []
        for e in entries where !(out.last.map { isSame($0, e) } ?? false) { out.append(e) }
        return out
    }

    static func group(_ entries: [HistoryEntry], now: Date = Date(), calendar: Calendar = .current,
                      locale: Locale = Locale(identifier: "es")) -> [HistoryDay] {
        let sorted = entries.sorted { $0.at != $1.at ? $0.at > $1.at : $0.id > $1.id }
        let fmt = DateFormatter()
        fmt.locale = locale
        fmt.setLocalizedDateFormatFromTemplate("EEEEdMMMMy")
        var days: [HistoryDay] = []
        for e in dedupe(sorted) {
            let d = calendar.startOfDay(for: Date(timeIntervalSince1970: e.at))
            if days.last?.day == d { days[days.count - 1].entries.append(e) } else {
                let title: String
                if calendar.isDate(d, inSameDayAs: now) { title = "Hoy" }
                else if let y = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now)), calendar.isDate(d, inSameDayAs: y) { title = "Ayer" }
                else { title = fmt.string(from: d).capitalized(with: locale) }
                days.append(HistoryDay(title: title, day: d, entries: [e]))
            }
        }
        return days
    }
}
