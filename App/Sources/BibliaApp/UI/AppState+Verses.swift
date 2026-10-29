import Foundation
import AppKit

/// Acciones sobre versículos: copiar, resaltar, marcar, anotar, referencias, comparar, Strong.
extension AppState {
    // MARK: contexto

    var actionContext: VerseActionContext {
        VerseActionContext(selectedCount: selectedVerses.count, strongAvailable: strongAvailable,
                           parallelOn: parallelOn, annotationsAvailable: annotations != nil)
    }

    func isEnabled(_ a: VerseAction) -> Bool { VerseActions.isEnabled(a, actionContext) }

    /// Contexto para un alcance explícito (clic derecho fuera de la selección).
    func actionContext(scope: Set<Int>?) -> VerseActionContext {
        var c = actionContext
        if let scope { c.selectedCount = scope.count }
        return c
    }

    /// Versículos reales a los que se aplica una acción: `scope` (clic derecho en un versículo no seleccionado)
    /// o la selección.
    func targetVerses(_ scope: Set<Int>? = nil) -> [Int] {
        VerseActions.verses(selected: scope ?? selectedVerses, items: items, parallel: parallelOn)
    }

    /// Un clic derecho sobre un versículo fuera de la selección actúa solo sobre ese versículo.
    func scope(forContextVerse v: Int?) -> Set<Int>? {
        guard let v, !selectedVerses.contains(v) else { return nil }
        return [v]
    }

    // MARK: anotaciones del capítulo

    func reloadAnnotations() {
        annotationVersion += 1
        chapterAnnotations = (try? annotations?.chapter(book: book, chapter: chapter)) ?? ChapterAnnotations()
        if let db = bible {
            crossRefCounts = (try? CrossRefRepository(db: db).counts(book: book, chapter: chapter)) ?? [:]
        } else { crossRefCounts = [:] }
    }

    /// Resaltado actual del conjunto: color común si todos coinciden.
    func highlightColor(of verses: [Int]) -> HighlightColor? {
        let cs = Set(verses.map { chapterAnnotations.highlights[$0] })
        return cs.count == 1 ? cs.first ?? nil : nil
    }

    func isBookmarked(_ verses: [Int]) -> Bool {
        !verses.isEmpty && verses.allSatisfy(chapterAnnotations.bookmarks.contains)
    }

    func selectionHasHighlight(scope: Set<Int>? = nil) -> Bool {
        targetVerses(scope).contains { chapterAnnotations.highlights[$0] != nil }
    }
    func selectionBookmarked(scope: Set<Int>? = nil) -> Bool { isBookmarked(targetVerses(scope)) }
    func selectionCrossRefCount(scope: Set<Int>? = nil) -> Int {
        let r = VerseActions.range(of: targetVerses(scope))
        return r.map { rg in rg.reduce(0) { $0 + (crossRefCounts[$1] ?? 0) } } ?? 0
    }

    // MARK: copiar

    func copySelectionPlain(scope: Set<Int>? = nil) {
        let sel = scope ?? selectedVerses
        let text: String?
        if glossMode {
            let cols = glossColumns.map { ($0.id, $0.language) }
            text = PlainCopy.text(rows: glossRows, selected: sel, columns: showGlosses ? cols : Array(cols.prefix(1)))
        } else if parallelOn {
            text = PlainCopy.text(rows: parallelRows, selected: sel, columns: parallelColumns.map { ($0.id, $0.language) })
        } else {
            let vs = items.filter { sel.contains($0.number) }
            text = vs.isEmpty ? nil : PlainCopy.text(verses: vs, language: language)
        }
        guard let text else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        toast = "Copiado"
    }

    func copyReference(scope: Set<Int>? = nil) {
        guard let s = scope else { copyWithReference(); return }
        let keep = selectedVerses
        selectedVerses = s; copyWithReference(); selectedVerses = keep
    }

    // MARK: resaltar / marcar

    func highlightSelection(_ color: HighlightColor, scope: Set<Int>? = nil) {
        let vs = targetVerses(scope)
        guard let store = annotations, !vs.isEmpty else { return }
        try? store.setHighlight(color, book: book, chapter: chapter, verses: vs)
        reloadAnnotations()
    }

    func highlightWithLastColor(scope: Set<Int>? = nil) {
        guard let store = annotations else { return }
        highlightSelection(store.lastUsedColor, scope: scope)
    }

    func removeHighlightSelection(scope: Set<Int>? = nil) {
        let vs = targetVerses(scope)
        guard let store = annotations, !vs.isEmpty else { return }
        try? store.removeHighlight(book: book, chapter: chapter, verses: vs)
        reloadAnnotations()
    }

    func toggleBookmarkSelection(scope: Set<Int>? = nil) {
        let vs = targetVerses(scope)
        guard let store = annotations, !vs.isEmpty else { return }
        let ch = SelectionAnnotating.bookmarkChanges(verses: vs, bookmarked: chapterAnnotations.bookmarks)
        for v in ch.add + ch.remove { _ = try? store.toggleBookmark(book: book, chapter: chapter, verse: v) }
        reloadAnnotations()
    }

    // MARK: notas / referencias (la tarea 5 rellena el contenido de las pestañas)

    func beginNote(for range: ClosedRange<Int>, selecting id: Int64? = nil) {
        noteTarget = range
        noteRequest = NoteRequest(token: noteRequest.token + 1, book: book, chapter: chapter, range: range, selecting: id)
        inspectorTab = .note
        showInspector = true
    }

    func showCrossRefs(for range: ClosedRange<Int>) {
        refsTarget = range
        refsBook = book; refsChapter = chapter
        inspectorTab = .refs
        showInspector = true
    }

    func beginNoteForSelection(scope: Set<Int>? = nil) {
        if let r = VerseActions.range(of: targetVerses(scope)) { beginNote(for: r) }
    }

    func showCrossRefsForSelection(scope: Set<Int>? = nil) {
        if let r = VerseActions.range(of: targetVerses(scope)) { showCrossRefs(for: r) }
    }

    // MARK: comparar / Strong

    /// Activa la vista paralela y se queda en el primer versículo seleccionado.
    func compareSelection(scope: Set<Int>? = nil) {
        guard let v = targetVerses(scope).first else { return }
        actionBarVisible = false
        if parallelOn { requestScroll(verse: v) } else {
            anchorVerse = v
            setParallel(true)
        }
        flash(verses: v...v)
    }

    /// Activa el modo Strong y abre la primera palabra con número del primer versículo seleccionado (KJV).
    func openStrongForSelection(scope: Set<Int>? = nil) {
        guard strongAvailable else { return }
        let vs = targetVerses(scope)
        setStrongMode(true)
        let first = vs.compactMap { v in strongSpans[v]?.first.map { (v, $0) } }.first
        actionBarVisible = false
        if let (v, sp) = first {
            strongSelection = StrongSelection(strong: sp.strong, verse: v, start: sp.start)
            strongWord = sp.word
            showStrong(sp.strong)
        } else {
            showInspector = true
            inspectorTab = .strong
        }
    }

    // MARK: despacho

    func perform(_ a: VerseAction, scope: Set<Int>? = nil) {
        switch a {
        case .copy: copySelectionPlain(scope: scope)
        case .copyReference: copyReference(scope: scope)
        case .highlight: highlightWithLastColor(scope: scope)
        case .note: beginNoteForSelection(scope: scope)
        case .bookmark: toggleBookmarkSelection(scope: scope)
        case .crossRefs: showCrossRefsForSelection(scope: scope)
        case .compare: compareSelection(scope: scope)
        case .strong: openStrongForSelection(scope: scope)
        }
    }

    /// Abre la nota desde el icono de nota del texto.
    func openNoteIcon(id: Int64) {
        if let n = chapterAnnotations.notes.first(where: { $0.id == id }) { beginNote(for: n.range, selecting: id) }
    }
}


// MARK: texto de versículos, referencias cruzadas y panel «Notas»

extension AppState {
    /// Texto de un rango en la versión actual (`nil` si ningún versículo existe en ella).
    func passageText(book b: Int, chapter c: Int, from: Int, to: Int) -> String? {
        guard let db = bible else { return nil }
        let vs = (try? VerseRepository(db: db).verses(translationId: translationId, book: b, chapter: c, from: from, to: to)) ?? []
        return CrossRefList.join(vs.map(\.text), language: language)
    }

    /// Referencias cruzadas de los versículos `refsTarget` (origen: `refsBook`/`refsChapter`), unidas y ordenadas por votos.
    func crossRefs() -> [CrossRef] {
        guard let db = bible, let r = refsTarget, refsBook > 0 else { return [] }
        let repo = CrossRefRepository(db: db)
        return CrossRefList.merge(r.map { (try? repo.refs(book: refsBook, chapter: refsChapter, verse: $0)) ?? [] })
    }

    func crossRefRow(_ r: CrossRef) -> CrossRefRow {
        CrossRefList.row(r, bookName: { self.bookName($0) },
                         text: { self.passageText(book: $0.book, chapter: $0.chapter, from: $0.verseFrom ?? 1, to: $0.verseTo ?? $0.verseFrom ?? 1) })
    }

    /// Navega a una referencia (historial «jump», destello); si el versículo no existe en la versión, queda en el capítulo.
    func navigate(to ref: BibleRef) {
        guard (1...66).contains(ref.book) else { return }
        searchTerms = []
        open(ref: ref)
    }

    func navigate(to item: AnnotationItem) {
        navigate(to: BibleRef(book: item.book, chapter: item.chapter, verseFrom: item.verseStart, verseTo: item.verseEnd))
        if item.kind == .note { beginNote(for: item.verseStart...max(item.verseStart, item.verseEnd), selecting: item.noteId) }
    }

    func referenceLabel(for item: AnnotationItem) -> String {
        RefLabel.text(bookName: bookName(item.book), chapter: item.chapter, from: item.verseStart, to: item.verseEnd)
    }
}
