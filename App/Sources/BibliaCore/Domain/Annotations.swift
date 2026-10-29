import Foundation

public enum HighlightColor: String, CaseIterable, Codable, Hashable, Identifiable {
    case yellow, green, blue, pink, orange
    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .yellow: "Amarillo"
        case .green: "Verde"
        case .blue: "Azul"
        case .pink: "Rosa"
        case .orange: "Naranja"
        }
    }
}

public struct Highlight: Hashable {
    public init(book: Int, chapter: Int, verse: Int, color: HighlightColor, updatedAt: Double) { self.book = book; self.chapter = chapter; self.verse = verse; self.color = color; self.updatedAt = updatedAt }
    public var book: Int, chapter: Int, verse: Int
    public var color: HighlightColor
    public var updatedAt: Double
}

public struct Bookmark: Hashable {
    public init(book: Int, chapter: Int, verse: Int, createdAt: Double) { self.book = book; self.chapter = chapter; self.verse = verse; self.createdAt = createdAt }
    public var book: Int, chapter: Int, verse: Int
    public var createdAt: Double
}

public struct Note: Hashable, Identifiable {
    public init(id: Int64, book: Int, chapter: Int, verseStart: Int, verseEnd: Int, body: String, createdAt: Double, updatedAt: Double) { self.id = id; self.book = book; self.chapter = chapter; self.verseStart = verseStart; self.verseEnd = verseEnd; self.body = body; self.createdAt = createdAt; self.updatedAt = updatedAt }
    public var id: Int64
    public var book: Int, chapter: Int
    public var verseStart: Int, verseEnd: Int
    public var body: String
    public var createdAt: Double, updatedAt: Double

    public var range: ClosedRange<Int> { verseStart...max(verseStart, verseEnd) }
    public func overlaps(_ r: ClosedRange<Int>) -> Bool { range.overlaps(r) }
    public func contains(verse: Int) -> Bool { range.contains(verse) }

    /// Primera línea no vacía, máx. ~60 caracteres.
    public var title: String {
        let line = body.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty } ?? ""
        return line.count > 60 ? String(line.prefix(60)) + "…" : line
    }
}

/// Anotaciones de un verso (o de un grupo de versos fusionados, p. ej. "20–21").
public struct VerseAnnotations: Equatable {
    public init(highlights: [Int: HighlightColor] = [:], notes: [Note] = [], bookmarkedVerses: [Int] = []) { self.highlights = highlights; self.notes = notes; self.bookmarkedVerses = bookmarkedVerses }
    public var highlights: [Int: HighlightColor] = [:]
    public var notes: [Note] = []
    public var bookmarkedVerses: [Int] = []
    /// Color del primer verso resaltado del grupo.
    public var color: HighlightColor? { highlights.keys.min().flatMap { highlights[$0] } }
    public var isBookmarked: Bool { !bookmarkedVerses.isEmpty }
    public var isEmpty: Bool { highlights.isEmpty && notes.isEmpty && bookmarkedVerses.isEmpty }
}

public struct ChapterAnnotations: Equatable {
    public init(highlights: [Int: HighlightColor] = [:], notes: [Note] = [], bookmarks: Set<Int> = []) { self.highlights = highlights; self.notes = notes; self.bookmarks = bookmarks }
    public var highlights: [Int: HighlightColor] = [:]
    public var notes: [Note] = []
    public var bookmarks: Set<Int> = []

    public func notes(overlapping verse: Int) -> [Note] { notes.filter { $0.contains(verse: verse) } }

    public func forDisplayVerse(number: Int, end: Int? = nil) -> VerseAnnotations {
        let r = number...max(number, end ?? number)
        var out = VerseAnnotations()
        for v in r {
            if let c = highlights[v] { out.highlights[v] = c }
            if bookmarks.contains(v) { out.bookmarkedVerses.append(v) }
        }
        out.notes = notes.filter { $0.overlaps(r) }
        return out
    }
}

public enum AnnotationKind: String, CaseIterable, Hashable { case note, highlight, bookmark }

public enum AnnotationSort { case canonical, updated }

public struct AnnotationFilter: Equatable {
    public init(kinds: Set<AnnotationKind> = Set(AnnotationKind.allCases), color: HighlightColor? = nil, book: Int? = nil, text: String = "", sort: AnnotationSort = .canonical) { self.kinds = kinds; self.color = color; self.book = book; self.text = text; self.sort = sort }
    public var kinds: Set<AnnotationKind> = Set(AnnotationKind.allCases)  // vacío = todos
    public var color: HighlightColor?
    public var book: Int?
    public var text: String = ""
    public var sort: AnnotationSort = .canonical
}

public struct AnnotationItem: Hashable, Identifiable {
    public init(kind: AnnotationKind, book: Int, chapter: Int, verseStart: Int, verseEnd: Int, color: HighlightColor? = nil, body: String? = nil, noteId: Int64? = nil, updatedAt: Double) { self.kind = kind; self.book = book; self.chapter = chapter; self.verseStart = verseStart; self.verseEnd = verseEnd; self.color = color; self.body = body; self.noteId = noteId; self.updatedAt = updatedAt }
    public var kind: AnnotationKind
    public var book: Int, chapter: Int
    public var verseStart: Int, verseEnd: Int
    public var color: HighlightColor?
    public var body: String?
    public var noteId: Int64?
    public var updatedAt: Double
    public var id: String { noteId.map { "n\($0)" } ?? "\(kind.rawValue)-\(book)-\(chapter)-\(verseStart)" }
}

public struct AnnotationCounts: Equatable {
    public var notes = 0, highlights = 0, bookmarks = 0
    public init(notes: Int = 0, highlights: Int = 0, bookmarks: Int = 0) { self.notes = notes; self.highlights = highlights; self.bookmarks = bookmarks }
}
