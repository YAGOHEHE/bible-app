import Foundation
import GRDB

public struct Translation: Codable, FetchableRecord, Identifiable, Hashable {
    public init(id: String, name: String, language: String, license: String? = nil, sourceURL: String? = nil, hasStrongs: Bool) { self.id = id; self.name = name; self.language = language; self.license = license; self.sourceURL = sourceURL; self.hasStrongs = hasStrongs }
    public var id: String
    public var name: String
    public var language: String        // zh | es | en
    public var license: String?
    public var sourceURL: String?
    public var hasStrongs: Bool

    public enum CodingKeys: String, CodingKey {
        case id, name, language, license
        case sourceURL = "source_url"
        case hasStrongs = "has_strongs"
    }
}

public struct BookName: Codable, FetchableRecord, Hashable {
    public init(book: Int, language: String, name: String, abbrev: String? = nil) { self.book = book; self.language = language; self.name = name; self.abbrev = abbrev }
    public var book: Int
    public var language: String
    public var name: String
    public var abbrev: String?
}

public struct Verse: Codable, FetchableRecord, Identifiable, Hashable {
    public init(translationId: String, book: Int, chapter: Int, verse: Int, text: String) { self.translationId = translationId; self.book = book; self.chapter = chapter; self.verse = verse; self.text = text }
    public var translationId: String
    public var book: Int
    public var chapter: Int
    public var verse: Int
    public var text: String
    public var id: String { "\(translationId)-\(book)-\(chapter)-\(verse)" }

    public enum CodingKeys: String, CodingKey {
        case translationId = "translation_id", book, chapter, verse, text
    }
}

public struct Heading: Codable, FetchableRecord, Hashable {
    public init(translationId: String, book: Int, chapter: Int, verse: Int, text: String, kind: String? = "s1") { self.translationId = translationId; self.book = book; self.chapter = chapter; self.verse = verse; self.text = text; self.kind = kind }
    public var translationId: String
    public var book: Int
    public var chapter: Int
    public var verse: Int          // el título se muestra antes de este versículo
    public var text: String
    public var kind: String? = "s1"   // ms | s1 | s2 | d | r

    public enum CodingKeys: String, CodingKey {
        case translationId = "translation_id", book, chapter, verse, text, kind
    }
}

/// Trozo de un versículo dentro de un bloque de maquetación (tabla `layout`).
/// `kind`: p | m | q | qr | li | pmo | b (abre bloque) o "+" (continúa el bloque anterior).
public struct LayoutPiece: Codable, FetchableRecord, Hashable {
    public init(seq: Int, kind: String, level: Int, verse: Int, text: String) { self.seq = seq; self.kind = kind; self.level = level; self.verse = verse; self.text = text }
    public var seq: Int
    public var kind: String
    public var level: Int
    public var verse: Int
    public var text: String
}

public struct VerseWord: Codable, FetchableRecord, Hashable {
    public init(translationId: String, book: Int, chapter: Int, verse: Int, idx: Int, word: String, strong: String? = nil) { self.translationId = translationId; self.book = book; self.chapter = chapter; self.verse = verse; self.idx = idx; self.word = word; self.strong = strong }
    public var translationId: String
    public var book: Int
    public var chapter: Int
    public var verse: Int
    public var idx: Int
    public var word: String
    public var strong: String?     // 'G25' / 'H430'

    public enum CodingKeys: String, CodingKey {
        case translationId = "translation_id", book, chapter, verse, idx, word, strong
    }
}

public struct LexiconEntry: Codable, FetchableRecord, Identifiable, Hashable {
    public init(id: String, lemma: String? = nil, translit: String? = nil, pronunciation: String? = nil, definition: String? = nil, kjvUsage: String? = nil) { self.id = id; self.lemma = lemma; self.translit = translit; self.pronunciation = pronunciation; self.definition = definition; self.kjvUsage = kjvUsage }
    public var id: String
    public var lemma: String?
    public var translit: String?
    public var pronunciation: String?
    public var definition: String?
    public var kjvUsage: String?

    public enum CodingKeys: String, CodingKey {
        case id, lemma, translit, pronunciation, definition
        case kjvUsage = "kjv_usage"
    }
}

/// Resultado de búsqueda: referencia + fragmento (con marcas «…» alrededor de la coincidencia).
public struct SearchHit: Hashable, Identifiable {
    public init(translationId: String, book: Int, chapter: Int, verse: Int, snippet: String, text: String = "") { self.translationId = translationId; self.book = book; self.chapter = chapter; self.verse = verse; self.snippet = snippet; self.text = text }
    public var translationId: String
    public var book: Int
    public var chapter: Int
    public var verse: Int
    public var snippet: String
    public var text: String = ""
    public var id: String { "\(translationId)-\(book)-\(chapter)-\(verse)" }
}

public struct HistoryEntry: Codable, FetchableRecord, Identifiable, Hashable {
    public init(id: Int64, translationId: String, book: Int, chapter: Int, verse: Int? = nil, kind: String, at: Double) { self.id = id; self.translationId = translationId; self.book = book; self.chapter = chapter; self.verse = verse; self.kind = kind; self.at = at }
    public var id: Int64
    public var translationId: String
    public var book: Int
    public var chapter: Int
    public var verse: Int?
    public var kind: String        // page | jump
    public var at: Double          // timeIntervalSince1970

    public enum CodingKeys: String, CodingKey {
        case id, book, chapter, verse, kind, at
        case translationId = "translation_id"
    }
}

/// Referencia bíblica (libro 1–66, capítulo, rango opcional de versículos).
public struct BibleRef: Equatable, Hashable {
    public init(book: Int, chapter: Int, verseFrom: Int? = nil, verseTo: Int? = nil) { self.book = book; self.chapter = chapter; self.verseFrom = verseFrom; self.verseTo = verseTo }
    public var book: Int
    public var chapter: Int
    public var verseFrom: Int?
    public var verseTo: Int?
}
