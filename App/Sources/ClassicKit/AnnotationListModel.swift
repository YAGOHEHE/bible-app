import Foundation
import BibliaCore

/// Chip de tipo del panel «Notas».
public enum AnnotationKindFilter: String, CaseIterable {
    case all, notes, highlights, bookmarks
    public var label: String {
        switch self {
        case .all: return "Todo"
        case .notes: return "Notas"
        case .highlights: return "Resaltados"
        case .bookmarks: return "Marcadores"
        }
    }
    public var kinds: Set<AnnotationKind> {
        switch self {
        case .all: return Set(AnnotationKind.allCases)
        case .notes: return [.note]
        case .highlights: return [.highlight]
        case .bookmarks: return [.bookmark]
        }
    }
    public func count(_ c: AnnotationCounts) -> Int {
        switch self {
        case .all: return c.notes + c.highlights + c.bookmarks
        case .notes: return c.notes
        case .highlights: return c.highlights
        case .bookmarks: return c.bookmarks
        }
    }
}

/// Modelo del panel «Notas» de la barra lateral: filtros, orden, lista y mutaciones.
public final class AnnotationListModel {
    public var store: AnnotationStore? { didSet { refresh() } }
    /// Tras borrar o recolorear (el lector repinta).
    public var onMutation: () -> Void = {}
    /// Tras recalcular la lista.
    public var onRefresh: () -> Void = {}

    public var kind: AnnotationKindFilter = .all { didSet { if kind != .highlights { color = nil }; refresh() } }
    public var color: HighlightColor? { didSet { refresh() } }
    public var book: Int? { didSet { refresh() } }
    public var text = "" { didSet { refresh() } }
    public var sort: AnnotationSort = .canonical { didSet { refresh() } }

    public private(set) var items: [AnnotationItem] = []
    public private(set) var counts = AnnotationCounts()

    public init(store: AnnotationStore? = nil) { self.store = store; refresh() }

    public var filter: AnnotationFilter { AnnotationFilter(kinds: kind.kinds, color: color, book: book, text: text, sort: sort) }

    public var isFiltered: Bool { kind != .all || color != nil || book != nil || !text.trimmingCharacters(in: .whitespaces).isEmpty }
    public var isSearching: Bool { !text.trimmingCharacters(in: .whitespaces).isEmpty }

    public func refresh() {
        if let s = store {
            items = (try? s.list(filter)) ?? []
            counts = (try? s.counts()) ?? AnnotationCounts()
        } else { items = []; counts = AnnotationCounts() }
        onRefresh()
    }

    public func clearFilters() {
        kind = .all; color = nil; book = nil; text = ""
    }

    // MARK: mutaciones

    public func delete(_ item: AnnotationItem) {
        guard let store = store else { return }
        switch item.kind {
        case .note: if let id = item.noteId { try? store.deleteNote(id: id) }
        case .highlight: try? store.removeHighlight(book: item.book, chapter: item.chapter, verses: [item.verseStart])
        case .bookmark: _ = try? store.toggleBookmark(book: item.book, chapter: item.chapter, verse: item.verseStart)
        }
        refresh(); onMutation()
    }

    public func recolor(_ item: AnnotationItem, to color: HighlightColor) {
        guard item.kind == .highlight, let store = store else { return }
        let last = store.lastUsedColor   // recolorear no cambia el «último color» de ⌥⌘H
        try? store.setHighlight(color, book: item.book, chapter: item.chapter, verses: [item.verseStart])
        store.lastUsedColor = last
        refresh(); onMutation()
    }

    /// Título de la nota sin marcas de Markdown (**, *, `, #, >, -).
    public static func title(of body: String) -> String {
        let t = Note(id: 0, book: 0, chapter: 0, verseStart: 0, verseEnd: 0, body: body, createdAt: 0, updatedAt: 0).title
        let cleaned = t.replacingOccurrences(of: "[*_`]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "^\\s*([#>\\-]+\\s*)+", with: "", options: .regularExpression)
        return cleaned.trimmingCharacters(in: .whitespaces)
    }
}
