import Foundation
import Observation

/// Petición de abrir el editor: rango (en un capítulo) y, opcionalmente, la nota a seleccionar.
struct NoteRequest: Equatable {
    var token = 0
    var book = 0
    var chapter = 0
    var range: ClosedRange<Int> = 1...1
    var selecting: Int64?
}

/// Editor de notas (pestaña «Nota»): lista de notas que solapan el rango, borrador, autoguardado con debounce.
@Observable
@MainActor
final class NoteEditorModel {
    nonisolated static let defaultDelay: UInt64 = 600_000_000

    @ObservationIgnored var store: AnnotationStore?
    /// Se llama tras cada escritura en la base (para refrescar iconos y panel).
    @ObservationIgnored var onChange: () -> Void = {}
    @ObservationIgnored let saveDelay: UInt64
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var loading = false

    private(set) var book = 0
    private(set) var chapter = 0
    /// Rango pedido: las notas nuevas se crean sobre él.
    private(set) var range: ClosedRange<Int> = 1...1
    private(set) var notes: [Note] = []
    private(set) var selectedId: Int64?
    private(set) var savedBody = ""
    private(set) var createdAt: Double?
    private(set) var updatedAt: Double?
    private(set) var errorMessage: String?
    var preview = false
    var focusToken = 0

    var draft = "" {
        didSet { if !loading, draft != oldValue { scheduleSave() } }
    }

    init(saveDelay: UInt64 = NoteEditorModel.defaultDelay) { self.saveDelay = saveDelay }

    var isDirty: Bool { draft.trimmingCharacters(in: .whitespacesAndNewlines) != savedBody }
    var hasTarget: Bool { book > 0 }
    var selectedNote: Note? { notes.first { $0.id == selectedId } }
    /// Rango de la nota seleccionada, o el pedido si es nueva.
    var editingRange: ClosedRange<Int> { selectedNote?.range ?? range }

    // MARK: abrir

    /// Guarda lo pendiente y abre el rango. Selecciona `selecting`; si no, la nota de rango idéntico, o la primera
    /// que solape; si no hay ninguna, un borrador nuevo.
    func load(book: Int, chapter: Int, range: ClosedRange<Int>, selecting: Int64? = nil) {
        flush()
        selectedId = nil
        self.book = book; self.chapter = chapter; self.range = range
        refreshNotes()
        let pick = notes.first { $0.id == selecting } ?? notes.first { $0.range == range } ?? notes.first
        if let pick { apply(pick) } else { startDraft() }
        focusToken += 1
    }

    func load(_ r: NoteRequest) { load(book: r.book, chapter: r.chapter, range: r.range, selecting: r.selecting) }

    func refreshNotes() {
        guard book > 0 else { notes = []; return }
        let all = (try? store?.chapter(book: book, chapter: chapter).notes) ?? []
        notes = all.filter { $0.overlaps(range) || $0.id == selectedId }
    }

    private func apply(_ n: Note) {
        loading = true
        selectedId = n.id
        draft = n.body
        savedBody = n.body
        createdAt = n.createdAt; updatedAt = n.updatedAt
        loading = false
    }

    private func startDraft() {
        loading = true
        selectedId = nil
        draft = ""; savedBody = ""
        createdAt = nil; updatedAt = nil
        loading = false
    }

    // MARK: acciones

    func select(_ id: Int64) {
        guard id != selectedId else { return }
        flush()
        refreshNotes()
        if let n = notes.first(where: { $0.id == id }) { apply(n) }
        focusToken += 1
    }

    func newNote() {
        flush()
        startDraft()
        focusToken += 1
    }

    /// Sustituye el borrador (equivale a teclear) y programa el guardado.
    func edit(_ text: String) { draft = text }

    func deleteSelected() {
        task?.cancel(); task = nil
        if let id = selectedId {
            do { try store?.deleteNote(id: id) } catch { errorMessage = "\(error)" }
        }
        refreshNotes()
        if let n = notes.first { apply(n) } else { startDraft() }
        onChange()
    }

    // MARK: guardado

    private func scheduleSave() {
        task?.cancel()
        let delay = saveDelay
        task = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delay)
            if Task.isCancelled { return }
            self?.flush()
        }
    }

    /// Guarda ya si hay cambios (cambio de pestaña, de nota, cierre). Cuerpo vacío = borra la nota.
    func flush() {
        task?.cancel(); task = nil
        guard let store, isDirty, hasTarget else { return }
        do {
            if let id = selectedId {
                if let n = try store.updateNote(id: id, body: draft) {
                    savedBody = n.body; updatedAt = n.updatedAt
                } else {
                    selectedId = nil; savedBody = ""; createdAt = nil; updatedAt = nil
                }
            } else if let n = try store.addNote(book: book, chapter: chapter, verseStart: range.lowerBound,
                                                verseEnd: range.upperBound, body: draft) {
                selectedId = n.id; savedBody = n.body; createdAt = n.createdAt; updatedAt = n.updatedAt
            } else {
                savedBody = ""
            }
            errorMessage = nil
        } catch {
            errorMessage = "No se pudo guardar la nota: \(error.localizedDescription)"
            return
        }
        refreshNotes()
        onChange()
    }
}
