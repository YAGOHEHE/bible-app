import Foundation

enum HighlightColor: String, CaseIterable, Codable, Hashable, Identifiable {
    case yellow, green, blue, pink, orange
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .yellow: "Amarillo"
        case .green: "Verde"
        case .blue: "Azul"
        case .pink: "Rosa"
        case .orange: "Naranja"
        }
    }
}

struct Highlight: Hashable {
    var book: Int, chapter: Int, verse: Int
    var color: HighlightColor
    var updatedAt: Double
}

struct Bookmark: Hashable {
    var book: Int, chapter: Int, verse: Int
    var createdAt: Double
}

struct Note: Hashable, Identifiable {
    var id: Int64
    var book: Int, chapter: Int
    var verseStart: Int, verseEnd: Int
    var body: String
    var createdAt: Double, updatedAt: Double

    var range: ClosedRange<Int> { verseStart...max(verseStart, verseEnd) }
    func overlaps(_ r: ClosedRange<Int>) -> Bool { range.overlaps(r) }
    func contains(verse: Int) -> Bool { range.contains(verse) }

    /// Primera línea no vacía, máx. ~60 caracteres.
    var title: String {
        let line = body.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty } ?? ""
        return line.count > 60 ? String(line.prefix(60)) + "…" : line
    }
}

/// Anotaciones de un verso (o de un grupo de versos fusionados, p. ej. "20–21").
struct VerseAnnotations: Equatable {
    var highlights: [Int: HighlightColor] = [:]
    var notes: [Note] = []
    var bookmarkedVerses: [Int] = []
    /// Color del primer verso resaltado del grupo.
    var color: HighlightColor? { highlights.keys.min().flatMap { highlights[$0] } }
    var isBookmarked: Bool { !bookmarkedVerses.isEmpty }
    var isEmpty: Bool { highlights.isEmpty && notes.isEmpty && bookmarkedVerses.isEmpty }
}

struct ChapterAnnotations: Equatable {
    var highlights: [Int: HighlightColor] = [:]
    var notes: [Note] = []
    var bookmarks: Set<Int> = []

    func notes(overlapping verse: Int) -> [Note] { notes.filter { $0.contains(verse: verse) } }

    func forDisplayVerse(number: Int, end: Int? = nil) -> VerseAnnotations {
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

enum AnnotationKind: String, CaseIterable, Hashable { case note, highlight, bookmark }

enum AnnotationSort { case canonical, updated }

struct AnnotationFilter: Equatable {
    var kinds: Set<AnnotationKind> = Set(AnnotationKind.allCases)  // vacío = todos
    var color: HighlightColor?
    var book: Int?
    var text: String = ""
    var sort: AnnotationSort = .canonical
}

struct AnnotationItem: Hashable, Identifiable {
    var kind: AnnotationKind
    var book: Int, chapter: Int
    var verseStart: Int, verseEnd: Int
    var color: HighlightColor?
    var body: String?
    var noteId: Int64?
    var updatedAt: Double
    var id: String { noteId.map { "n\($0)" } ?? "\(kind.rawValue)-\(book)-\(chapter)-\(verseStart)" }
}

struct AnnotationCounts: Equatable { var notes = 0, highlights = 0, bookmarks = 0 }
