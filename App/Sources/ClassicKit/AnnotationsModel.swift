import Foundation
import BibliaCore

public extension Notification.Name {
    /// Cambió la selección de versículos.
    static let classicSelectionChanged = Notification.Name("org.biblia.clasica.selectionChanged")
    /// Se escribió en la base de anotaciones (resaltado, marcador o nota) o cambió el capítulo mostrado.
    static let classicAnnotationsChanged = Notification.Name("org.biblia.clasica.annotationsChanged")
}

/// Selección de versículos + anotaciones del capítulo + acciones sobre ellas (sin UI).
/// Las anotaciones se guardan por referencia (libro·capítulo·versículo), independientes de la versión.
public final class AnnotationsModel {
    public let store: AnnotationStore?
    public let reader: ReaderModel
    private let center: NotificationCenter

    public private(set) var selection = VerseSelection()
    /// La barra de acciones está abierta (se abre con un clic en un versículo; × / Esc la cierran).
    public private(set) var barVisible = false
    /// Números de fila mostrados (para el ⇧-clic) y si son filas exactas (columnas / glosas) o elementos de la lectura simple.
    public var rows: [Int] = []
    public var rowsAreExact = false

    private var cached: ChapterAnnotations?
    private var cachedKey = [0, 0, -1]
    private var version = 0
    private var refCounts: [Int: Int] = [:]
    private var refCountsKey = [0, 0]
    private var lastChapter = [0, 0]
    private var tokens: [NSObjectProtocol] = []

    public init(reader: ReaderModel, store: AnnotationStore?, center: NotificationCenter = .default) {
        self.reader = reader; self.store = store; self.center = center
        lastChapter = [reader.book, reader.chapter]
        tokens.append(center.addObserver(forName: .classicChapterChanged, object: reader, queue: nil) { [weak self] _ in
            self?.chapterChanged()
        })
    }
    deinit { tokens.forEach { center.removeObserver($0) } }

    // MARK: selección

    public var selectedRows: Set<Int> { selection.selected }

    private func selectionChanged() { center.post(name: .classicSelectionChanged, object: self) }

    public func click(_ n: Int, shift: Bool) {
        selection.click(n, shift: shift, rows: rows)
        if selection.contains(n) { barVisible = true }
        if selection.isEmpty { barVisible = false }
        selectionChanged()
    }

    public func clearSelection() {
        guard !selection.isEmpty || barVisible else { return }
        selection.clear(); barVisible = false
        selectionChanged()
    }

    public func closeBar() {
        guard barVisible else { return }
        barVisible = false
        selectionChanged()
    }

    private func chapterChanged() {
        let now = [reader.book, reader.chapter]
        if now != lastChapter { lastChapter = now; clearSelection() }
    }

    // MARK: anotaciones del capítulo

    public var annotationsAvailable: Bool { store != nil }

    /// Anotaciones del capítulo mostrado (se recargan solas al cambiar de capítulo o tras una escritura).
    public var chapter: ChapterAnnotations {
        let key = [reader.book, reader.chapter, version]
        if cached == nil || key != cachedKey {
            cached = (try? store?.chapter(book: reader.book, chapter: reader.chapter)) ?? ChapterAnnotations()
            cachedKey = key
        }
        return cached ?? ChapterAnnotations()
    }

    /// Avisa de una escritura en la base (también la hace el editor de notas y el panel Notas).
    public func didMutate() {
        version += 1
        center.post(name: .classicAnnotationsChanged, object: self)
    }

    public var crossRefCounts: [Int: Int] {
        let key = [reader.book, reader.chapter]
        if key != refCountsKey || refCounts.isEmpty {
            refCountsKey = key
            refCounts = reader.bible.flatMap { try? CrossRefRepository(db: $0).counts(book: key[0], chapter: key[1]) } ?? [:]
        }
        return refCounts
    }

    // MARK: ámbito de las acciones

    /// Versículos reales de una acción: `scope` (clic derecho en un versículo sin seleccionar) o la selección.
    public func targetVerses(_ scope: Set<Int>? = nil) -> [Int] {
        VerseActions.verses(selected: scope ?? selection.selected, items: reader.items, parallel: rowsAreExact)
    }

    /// Un clic derecho sobre un versículo fuera de la selección actúa solo sobre ese versículo.
    public func scope(forContextVerse v: Int?) -> Set<Int>? {
        guard let v = v, !selection.contains(v) else { return nil }
        return [v]
    }

    public func context(scope: Set<Int>? = nil, strongAvailable: Bool, parallelOn: Bool) -> VerseActionContext {
        VerseActionContext(selectedCount: (scope ?? selection.selected).count, strongAvailable: strongAvailable,
                           parallelOn: parallelOn, annotationsAvailable: annotationsAvailable)
    }

    public func range(scope: Set<Int>? = nil) -> ClosedRange<Int>? { VerseActions.range(of: targetVerses(scope)) }

    public func highlightColor(scope: Set<Int>? = nil) -> HighlightColor? {
        let vs = targetVerses(scope)
        let cs = Set(vs.map { chapter.highlights[$0] })
        return cs.count == 1 ? cs.first ?? nil : nil
    }
    public func hasHighlight(scope: Set<Int>? = nil) -> Bool { targetVerses(scope).contains { chapter.highlights[$0] != nil } }
    public func isBookmarked(scope: Set<Int>? = nil) -> Bool {
        let vs = targetVerses(scope)
        return !vs.isEmpty && vs.allSatisfy(chapter.bookmarks.contains)
    }
    public func crossRefCount(scope: Set<Int>? = nil) -> Int {
        guard let r = range(scope: scope) else { return 0 }
        let c = crossRefCounts
        return r.reduce(0) { $0 + (c[$1] ?? 0) }
    }

    public func menuState(scope: Set<Int>? = nil, strongAvailable: Bool, parallelOn: Bool) -> VerseMenuState {
        VerseMenuState(context: context(scope: scope, strongAvailable: strongAvailable, parallelOn: parallelOn),
                       bookmarked: isBookmarked(scope: scope), hasHighlight: hasHighlight(scope: scope),
                       crossRefCount: crossRefCount(scope: scope), hasVerseSelection: !selection.isEmpty)
    }

    // MARK: escrituras

    public func highlight(_ color: HighlightColor, scope: Set<Int>? = nil) {
        let vs = targetVerses(scope)
        guard let s = store, !vs.isEmpty else { return }
        try? s.setHighlight(color, book: reader.book, chapter: reader.chapter, verses: vs)
        didMutate()
    }

    public func highlightWithLastColor(scope: Set<Int>? = nil) {
        guard let s = store else { return }
        highlight(s.lastUsedColor, scope: scope)
    }

    public func removeHighlight(scope: Set<Int>? = nil) {
        let vs = targetVerses(scope)
        guard let s = store, !vs.isEmpty else { return }
        try? s.removeHighlight(book: reader.book, chapter: reader.chapter, verses: vs)
        didMutate()
    }

    public func toggleBookmark(scope: Set<Int>? = nil) {
        let vs = targetVerses(scope)
        guard let s = store, !vs.isEmpty else { return }
        let ch = SelectionAnnotating.bookmarkChanges(verses: vs, bookmarked: chapter.bookmarks)
        for v in ch.add + ch.remove { _ = try? s.toggleBookmark(book: reader.book, chapter: reader.chapter, verse: v) }
        didMutate()
    }
}
