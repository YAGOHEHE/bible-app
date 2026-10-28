import Foundation
import GRDB

struct Translation: Codable, FetchableRecord, Identifiable, Hashable {
    var id: String
    var name: String
    var language: String        // zh | es | en
    var license: String?
    var sourceURL: String?
    var hasStrongs: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, language, license
        case sourceURL = "source_url"
        case hasStrongs = "has_strongs"
    }
}

struct BookName: Codable, FetchableRecord, Hashable {
    var book: Int
    var language: String
    var name: String
    var abbrev: String?
}

struct Verse: Codable, FetchableRecord, Identifiable, Hashable {
    var translationId: String
    var book: Int
    var chapter: Int
    var verse: Int
    var text: String
    var id: String { "\(translationId)-\(book)-\(chapter)-\(verse)" }

    enum CodingKeys: String, CodingKey {
        case translationId = "translation_id", book, chapter, verse, text
    }
}

struct Heading: Codable, FetchableRecord, Hashable {
    var translationId: String
    var book: Int
    var chapter: Int
    var verse: Int          // el título se muestra antes de este versículo
    var text: String
    var kind: String? = "s1"   // ms | s1 | s2 | d | r

    enum CodingKeys: String, CodingKey {
        case translationId = "translation_id", book, chapter, verse, text, kind
    }
}

/// Trozo de un versículo dentro de un bloque de maquetación (tabla `layout`).
/// `kind`: p | m | q | qr | li | pmo | b (abre bloque) o "+" (continúa el bloque anterior).
struct LayoutPiece: Codable, FetchableRecord, Hashable {
    var seq: Int
    var kind: String
    var level: Int
    var verse: Int
    var text: String
}

struct VerseWord: Codable, FetchableRecord, Hashable {
    var translationId: String
    var book: Int
    var chapter: Int
    var verse: Int
    var idx: Int
    var word: String
    var strong: String?     // 'G25' / 'H430'

    enum CodingKeys: String, CodingKey {
        case translationId = "translation_id", book, chapter, verse, idx, word, strong
    }
}

struct LexiconEntry: Codable, FetchableRecord, Identifiable, Hashable {
    var id: String
    var lemma: String?
    var translit: String?
    var pronunciation: String?
    var definition: String?
    var kjvUsage: String?

    enum CodingKeys: String, CodingKey {
        case id, lemma, translit, pronunciation, definition
        case kjvUsage = "kjv_usage"
    }
}

/// Resultado de búsqueda: referencia + fragmento (con marcas «…» alrededor de la coincidencia).
struct SearchHit: Hashable, Identifiable {
    var translationId: String
    var book: Int
    var chapter: Int
    var verse: Int
    var snippet: String
    var id: String { "\(translationId)-\(book)-\(chapter)-\(verse)" }
}

struct HistoryEntry: Codable, FetchableRecord, Identifiable, Hashable {
    var id: Int64
    var translationId: String
    var book: Int
    var chapter: Int
    var verse: Int?
    var kind: String        // page | jump
    var at: Double          // timeIntervalSince1970

    enum CodingKeys: String, CodingKey {
        case id, book, chapter, verse, kind, at
        case translationId = "translation_id"
    }
}

/// Referencia bíblica (libro 1–66, capítulo, rango opcional de versículos).
struct BibleRef: Equatable, Hashable {
    var book: Int
    var chapter: Int
    var verseFrom: Int?
    var verseTo: Int?
}
