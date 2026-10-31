import BibliaCore
import Foundation

/// Modelo de las pestañas de texto del inspector (puro).
enum InspectorTabModel {
    /// Número que acompaña al título (solo «Referencias», y solo si hay alguna).
    static func badge(_ tab: InspectorTab, refsCount: Int) -> Int? { tab == .refs && refsCount > 0 ? refsCount : nil }

    static func title(_ tab: InspectorTab, refsCount: Int) -> String {
        badge(tab, refsCount: refsCount).map { "\(tab.label) \($0)" } ?? tab.label
    }
}

/// Otra palabra con número Strong del versículo abierto, mostrada como cápsula pulsable.
struct StrongWordCapsule: Identifiable, Equatable {
    var word: String
    var strong: String
    var start: Int
    var id: Int { start }
}

enum StrongVerseWords {
    /// Palabras con número del versículo salvo la abierta (y las que comparten su número), sin repetir (palabra, número).
    static func capsules(spans: [StrongSpan], active: StrongSelection?) -> [StrongWordCapsule] {
        var seen = Set<String>()
        var out: [StrongWordCapsule] = []
        for s in spans.sorted(by: { $0.start < $1.start }) {
            if let a = active, s.start == a.start || s.strong == a.strong { continue }
            guard seen.insert(s.word.lowercased() + "|" + s.strong).inserted else { continue }
            out.append(StrongWordCapsule(word: s.word, strong: s.strong, start: s.start))
        }
        return out
    }
}
