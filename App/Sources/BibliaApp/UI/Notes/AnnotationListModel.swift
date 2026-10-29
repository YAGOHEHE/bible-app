import BibliaCore
import Foundation
import Observation

/// Chip de tipo del panel «Notas».
enum AnnotationKindFilter: String, CaseIterable, Identifiable {
    case all, notes, highlights, bookmarks
    var id: String { rawValue }
    var label: String {
        switch self {
        case .all: "Todo"
        case .notes: "Notas"
        case .highlights: "Resaltados"
        case .bookmarks: "Marcadores"
        }
    }
    var kinds: Set<AnnotationKind> {
        switch self {
        case .all: Set(AnnotationKind.allCases)
        case .notes: [.note]
        case .highlights: [.highlight]
        case .bookmarks: [.bookmark]
        }
    }
    func count(_ c: AnnotationCounts) -> Int {
        switch self {
        case .all: c.notes + c.highlights + c.bookmarks
        case .notes: c.notes
        case .highlights: c.highlights
        case .bookmarks: c.bookmarks
        }
    }
}

/// Modelo del panel «Notas» de la barra lateral: filtros, orden, lista y mutaciones.
@Observable
@MainActor
final class AnnotationListModel {
    @ObservationIgnored var store: AnnotationStore? { didSet { refresh() } }
    /// Tras borrar o recolorear (para que el lector repinte).
    @ObservationIgnored var onMutation: () -> Void = {}

    var kind: AnnotationKindFilter = .all { didSet { if kind != .highlights { color = nil }; refresh() } }
    var color: HighlightColor? { didSet { refresh() } }
    var book: Int? { didSet { refresh() } }
    var text = "" { didSet { refresh() } }
    var sort: AnnotationSort = .canonical { didSet { refresh() } }

    private(set) var items: [AnnotationItem] = []
    private(set) var counts = AnnotationCounts()

    var filter: AnnotationFilter {
        AnnotationFilter(kinds: kind.kinds, color: color, book: book, text: text, sort: sort)
    }

    /// Con texto de búsqueda solo se pueden encontrar notas.
    var isFiltered: Bool { kind != .all || color != nil || book != nil || !text.trimmingCharacters(in: .whitespaces).isEmpty }

    func refresh() {
        guard let store else { items = []; counts = AnnotationCounts(); return }
        items = (try? store.list(filter)) ?? []
        counts = (try? store.counts()) ?? AnnotationCounts()
    }

    func clearFilters() {
        kind = .all; color = nil; book = nil; text = ""
    }

    // MARK: mutaciones

    func delete(_ item: AnnotationItem) {
        guard let store else { return }
        switch item.kind {
        case .note: if let id = item.noteId { try? store.deleteNote(id: id) }
        case .highlight: try? store.removeHighlight(book: item.book, chapter: item.chapter, verses: [item.verseStart])
        case .bookmark: _ = try? store.toggleBookmark(book: item.book, chapter: item.chapter, verse: item.verseStart)
        }
        refresh(); onMutation()
    }

    func recolor(_ item: AnnotationItem, to color: HighlightColor) {
        guard item.kind == .highlight, let store else { return }
        let last = store.lastUsedColor   // recolorear no cambia el «último color» de ⌥⌘H
        try? store.setHighlight(color, book: item.book, chapter: item.chapter, verses: [item.verseStart])
        store.lastUsedColor = last
        refresh(); onMutation()
    }
}
