import Foundation
import BibliaCore

/// Petición de abrir el editor: rango (en un capítulo) y, opcionalmente, la nota a seleccionar.
public struct NoteRequest: Equatable {
    public var book = 0
    public var chapter = 0
    public var range: ClosedRange<Int> = 1...1
    public var selecting: Int64?
    public init(book: Int, chapter: Int, range: ClosedRange<Int>, selecting: Int64? = nil) {
        self.book = book; self.chapter = chapter; self.range = range; self.selecting = selecting
    }
}

/// Editor de notas (pestaña «Nota»): notas que solapan el rango, borrador y autoguardado con debounce (600 ms).
/// Sin Swift Concurrency: el temporizador es un `DispatchWorkItem` en la cola principal.
public final class NoteEditorModel {
    public static let defaultDelay: TimeInterval = 0.6

    public var store: AnnotationStore?
    /// Tras cada escritura en la base (refresca iconos y panel).
    public var onChange: () -> Void = {}
    /// Tras cualquier cambio de estado visible (borrador, estado de guardado, nota seleccionada).
    public var onState: () -> Void = {}
    public let saveDelay: TimeInterval
    /// Programa el guardado diferido (los tests lo sustituyen para no esperar).
    public var schedule: (TimeInterval, DispatchWorkItem) -> Void = { delay, work in
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }
    private var pending: DispatchWorkItem?
    private var loading = false

    public private(set) var book = 0
    public private(set) var chapter = 0
    /// Rango pedido: las notas nuevas se crean sobre él.
    public private(set) var range: ClosedRange<Int> = 1...1
    public private(set) var notes: [Note] = []
    public private(set) var selectedId: Int64?
    public private(set) var savedBody = ""
    public private(set) var createdAt: Double?
    public private(set) var updatedAt: Double?
    public private(set) var errorMessage: String?
    public var preview = false { didSet { onState() } }

    public private(set) var draft = ""

    public init(saveDelay: TimeInterval = NoteEditorModel.defaultDelay) { self.saveDelay = saveDelay }

    public var isDirty: Bool { draft.trimmingCharacters(in: .whitespacesAndNewlines) != savedBody }
    public var hasTarget: Bool { book > 0 }
    public var selectedNote: Note? { notes.first { $0.id == selectedId } }
    /// Rango de la nota seleccionada, o el pedido si es nueva.
    public var editingRange: ClosedRange<Int> { selectedNote?.range ?? range }
    public var hasPendingSave: Bool { pending != nil }

    /// «Guardando…» / «Guardada» / «Sin guardar».
    public var statusText: String { isDirty ? "Guardando…" : (selectedId == nil ? "Sin guardar" : "Guardada") }

    // MARK: abrir

    /// Guarda lo pendiente y abre el rango. Selecciona `selecting`; si no, la nota de rango idéntico, o la primera
    /// que solape; si no hay ninguna, un borrador nuevo.
    public func load(book: Int, chapter: Int, range: ClosedRange<Int>, selecting: Int64? = nil) {
        flush()
        selectedId = nil
        self.book = book; self.chapter = chapter; self.range = range
        refreshNotes()
        let pick = notes.first { $0.id == selecting } ?? notes.first { $0.range == range } ?? notes.first
        if let pick = pick { apply(pick) } else { startDraft() }
        onState()
    }

    public func load(_ r: NoteRequest) { load(book: r.book, chapter: r.chapter, range: r.range, selecting: r.selecting) }

    public func refreshNotes() {
        guard book > 0 else { notes = []; return }
        let all = (try? store?.chapter(book: book, chapter: chapter).notes) ?? []
        notes = all.filter { $0.overlaps(range) || $0.id == selectedId }
    }

    private func apply(_ n: Note) {
        selectedId = n.id
        draft = n.body; savedBody = n.body
        createdAt = n.createdAt; updatedAt = n.updatedAt
    }

    private func startDraft() {
        selectedId = nil
        draft = ""; savedBody = ""
        createdAt = nil; updatedAt = nil
    }

    // MARK: acciones

    public func select(_ id: Int64) {
        guard id != selectedId else { return }
        flush()
        refreshNotes()
        if let n = notes.first(where: { $0.id == id }) { apply(n) }
        onState()
    }

    public func newNote() {
        flush()
        startDraft()
        onState()
    }

    /// Sustituye el borrador (equivale a teclear) y programa el guardado.
    public func edit(_ text: String) {
        guard text != draft else { return }
        draft = text
        scheduleSave()
        onState()
    }

    public func deleteSelected() {
        cancelPending()
        if let id = selectedId {
            do { try store?.deleteNote(id: id) } catch { errorMessage = "\(error)" }
        }
        refreshNotes()
        if let n = notes.first { apply(n) } else { startDraft() }
        onChange()
        onState()
    }

    // MARK: guardado

    private func cancelPending() { pending?.cancel(); pending = nil }

    private func scheduleSave() {
        cancelPending()
        let w = DispatchWorkItem { [weak self] in self?.pending = nil; self?.flush() }
        pending = w
        schedule(saveDelay, w)
    }

    /// Guarda ya si hay cambios (cambio de pestaña, de nota, cierre, salir). Cuerpo vacío = borra la nota.
    public func flush() {
        cancelPending()
        guard let store = store, isDirty, hasTarget else { return }
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
            onState()
            return
        }
        refreshNotes()
        onChange()
        onState()
    }
}
