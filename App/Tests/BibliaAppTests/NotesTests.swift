import Testing
import Foundation
@testable import BibliaApp

private func makeStore() throws -> AnnotationStore {
    let u = try UserStore(path: NSTemporaryDirectory() + "notes-\(UUID().uuidString).sqlite")
    return AnnotationStore(user: u, defaults: UserDefaults(suiteName: "notes-\(UUID().uuidString)")!)
}

@MainActor private func makeEditor(delayMs: UInt64 = 30) throws -> (NoteEditorModel, AnnotationStore) {
    let s = try makeStore()
    let m = NoteEditorModel(saveDelay: delayMs * 1_000_000)
    m.store = s
    return (m, s)
}

private func wait(_ ms: UInt64) async { try? await Task.sleep(nanoseconds: ms * 1_000_000) }

@MainActor @Suite struct NoteEditorTests {
    @Test func autosaveIsDebounced() async throws {
        let (m, s) = try makeEditor(delayMs: 80)
        var changes = 0
        m.onChange = { changes += 1 }
        m.load(book: 45, chapter: 8, range: 28...28)
        m.edit("H"); m.edit("Ho"); m.edit("Hola")
        #expect(try s.counts().notes == 0)          // aún no: debounce
        await wait(30); m.edit("Hola mundo")        // reinicia el temporizador
        await wait(50)
        #expect(try s.counts().notes == 0)
        await wait(150)
        let n = try #require(try s.chapter(book: 45, chapter: 8).notes.first)
        #expect(n.body == "Hola mundo" && n.range == 28...28)
        #expect(try s.counts().notes == 1 && changes == 1)
        #expect(!m.isDirty && m.selectedId == n.id)
        m.edit("Hola mundo!"); await wait(200)       // edición posterior = actualización, no nota nueva
        #expect(try s.counts().notes == 1)
        #expect(try s.note(id: n.id)?.body == "Hola mundo!")
    }

    @Test func flushSavesOnTabSwitchAndLoad() async throws {
        let (m, s) = try makeEditor(delayMs: 10_000)   // el temporizador nunca llega
        m.load(book: 43, chapter: 3, range: 16...16)
        m.edit("pendiente")
        #expect(try s.counts().notes == 0 && m.isDirty)
        m.flush()
        #expect(try s.counts().notes == 1)
        m.edit("otra cosa")
        m.load(book: 43, chapter: 3, range: 17...17)   // cambiar de versículo guarda antes
        #expect(try s.chapter(book: 43, chapter: 3).notes.first?.body == "otra cosa")
        #expect(m.selectedId == nil && m.draft.isEmpty)  // el 17 no tiene nota: borrador vacío
    }

    @Test func emptyBodyDeletesAndNeverCreates() async throws {
        let (m, s) = try makeEditor()
        m.load(book: 1, chapter: 1, range: 1...2)
        m.edit("   \n "); m.flush()
        #expect(try s.counts().notes == 0)
        m.edit("algo"); m.flush()
        #expect(try s.counts().notes == 1)
        let id = try #require(m.selectedId)
        m.edit("  "); m.flush()                      // vaciar = borrar
        #expect(try s.counts().notes == 0 && m.selectedId == nil)
        #expect(try s.note(id: id) == nil)
    }

    @Test func severalNotesPerRangeAndSelection() async throws {
        let (m, s) = try makeEditor()
        try s.addNote(book: 45, chapter: 8, verseStart: 28, body: "A")
        try s.addNote(book: 45, chapter: 8, verseStart: 26, verseEnd: 30, body: "B (rango)")
        try s.addNote(book: 45, chapter: 8, verseStart: 40, body: "lejos")
        m.load(book: 45, chapter: 8, range: 28...28)
        #expect(m.notes.map(\.body) == ["B (rango)", "A"])   // solapan el 28 (orden por versículo inicial)
        #expect(m.selectedNote?.body == "A")                 // rango idéntico primero
        m.select(m.notes[0].id)
        #expect(m.draft == "B (rango)" && m.editingRange == 26...30)
        m.edit("B2"); m.newNote()                            // «Nueva nota» guarda la actual y abre un borrador
        #expect(try s.chapter(book: 45, chapter: 8).notes.contains { $0.body == "B2" })
        #expect(m.selectedId == nil && m.draft.isEmpty && m.editingRange == 28...28)
        m.edit("C"); m.flush()
        #expect(m.notes.count == 3)
        // pedir una nota concreta
        m.load(book: 45, chapter: 8, range: 28...28, selecting: m.notes.first { $0.body == "B2" }?.id)
        #expect(m.draft == "B2")
    }

    @Test func deleteSelectedFlow() async throws {
        let (m, s) = try makeEditor()
        try s.addNote(book: 1, chapter: 1, verseStart: 1, body: "uno")
        try s.addNote(book: 1, chapter: 1, verseStart: 1, body: "dos")
        var changes = 0; m.onChange = { changes += 1 }
        m.load(book: 1, chapter: 1, range: 1...1)
        let first = try #require(m.selectedId)
        m.deleteSelected()
        #expect(try s.note(id: first) == nil && s.counts().notes == 1 && changes == 1)
        #expect(m.selectedId != nil && m.notes.count == 1)   // pasa a la otra
        m.deleteSelected()
        #expect(try s.counts().notes == 0 && m.selectedId == nil && m.draft.isEmpty)
    }

    @Test func timestampsAreKept() async throws {
        let (m, s) = try makeEditor()
        try s.addNote(book: 1, chapter: 1, verseStart: 1, body: "x", at: 1000)
        m.load(book: 1, chapter: 1, range: 1...1)
        #expect(m.createdAt == 1000 && m.updatedAt == 1000)
        m.edit("y"); m.flush()
        #expect(m.createdAt == 1000 && (m.updatedAt ?? 0) > 1000)
    }

    @Test func markdownPreviewNeverThrows() {
        let odd = ["", "**sin cerrar", "[x](", "\u{0}\u{1F600}汉字 *a*", String(repeating: "# ", count: 5000), "```\n``", "![img](nope)",
                   "<b>html</b> & más", "\n\n\n- a\n  - b\n1. c"]
        for s in odd { _ = MarkdownPreview.render(s) }
        #expect(String(MarkdownPreview.render("**negrita**").characters) == "negrita")
        #expect(String(MarkdownPreview.render("a\nb").characters).contains("\n"))   // conserva saltos
    }
}

@Suite struct RefsListTests {
    func ref(_ v: Int, _ tb: Int, _ tc: Int, _ ts: Int, _ te: Int, _ votes: Int) -> CrossRef {
        CrossRef(book: 43, chapter: 3, verse: v, toBook: tb, toChapter: tc, toVerseStart: ts, toVerseEnd: te, votes: votes)
    }

    @Test func mergeOrdersByVotesAndDedupes() {
        let a = [ref(16, 62, 4, 9, 10, 50), ref(16, 45, 5, 8, 8, 120), ref(16, 1, 1, 1, 1, 50)]
        let b = [ref(17, 45, 5, 8, 8, 200), ref(17, 40, 1, 1, 1, 7)]
        let m = CrossRefList.merge([a, b])
        #expect(m.map(\.toBook) == [45, 1, 62, 40])           // 200, 50 (Gn antes de 1 Jn), 50, 7
        #expect(m[0].votes == 200 && m.count == 4)
        #expect(CrossRefList.merge([]).isEmpty)
    }

    @Test func rangeFormattingInThreeLanguages() {
        #expect(RefLabel.text(bookName: "1 Juan", chapter: 4, from: 9, to: 10) == "1 Juan 4:9–10")
        #expect(RefLabel.text(bookName: "1 John", chapter: 4, from: 9, to: 9) == "1 John 4:9")
        #expect(RefLabel.text(bookName: "约翰一书", chapter: 4, from: 9, to: 10) == "约翰一书 4:9–10")
        #expect(RefLabel.text(bookName: "Juan", chapter: 3, from: nil, to: nil) == "Juan 3")
        #expect(RefLabel.text(bookName: "Juan", chapter: 3, from: 16, to: nil) == "Juan 3:16")
        #expect(RefLabel.text(bookName: "Salmos", ref: BibleRef(book: 19, chapter: 23, verseFrom: 1, verseTo: 3)) == "Salmos 23:1–3")
    }

    @Test func rowsHandleMissingTargetVerses() {
        let r = CrossRef(book: 43, chapter: 3, verse: 16, toBook: 62, toChapter: 4, toVerseStart: 9, toVerseEnd: 10, votes: 9)
        let found = CrossRefList.row(r, bookName: { _ in "1 Juan" }, text: { _ in "Dios es amor" })
        #expect(found.label == "1 Juan 4:9–10" && found.snippet == "Dios es amor" && found.votes == 9)
        let missing = CrossRefList.row(r, bookName: { _ in "1 Juan" }, text: { _ in nil })
        #expect(missing.snippet == nil && missing.label == "1 Juan 4:9–10")   // la vista muestra «—»
        #expect(CrossRefList.join(["  ", ""], language: "es") == nil)
        #expect(CrossRefList.join(["你好", "世界"], language: "zh") == "你好世界")
        #expect(CrossRefList.join(["a", "b"], language: "en") == "a b")
    }

    @Test func realDataJohn316() throws {
        guard let p = BibleDatabase.bundledPath() else { return }
        let db = try BibleDatabase(path: p)
        let refs = try CrossRefRepository(db: db).refs(book: 43, chapter: 3, verse: 16)
        #expect(!refs.isEmpty)
        #expect(zip(refs, refs.dropFirst()).allSatisfy { $0.votes >= $1.votes })
        #expect(CrossRefList.merge([refs]).count <= refs.count)
        // el texto de un destino existe en CUV y puede faltar un versículo fuera de numeración
        let vs = try VerseRepository(db: db).verses(translationId: "CUV", book: 43, chapter: 3, from: 16, to: 16)
        #expect(vs.count == 1)
        let none = try VerseRepository(db: db).verses(translationId: "CUV", book: 43, chapter: 3, from: 900, to: 901)
        #expect(none.isEmpty)
    }
}

@MainActor @Suite struct AnnotationListTests {
    func seeded() throws -> (AnnotationListModel, AnnotationStore) {
        let s = try makeStore()
        try s.addNote(book: 45, chapter: 8, verseStart: 28, body: "Todo ayuda a bien", at: 100)
        try s.addNote(book: 43, chapter: 3, verseStart: 16, body: "永生 de Juan", at: 300)
        try s.setHighlight(.yellow, book: 43, chapter: 3, verses: [16, 17], at: 200)
        try s.setHighlight(.green, book: 1, chapter: 1, verses: [1], at: 50)
        try s.toggleBookmark(book: 19, chapter: 23, verse: 1)
        let m = AnnotationListModel()
        m.store = s
        return (m, s)
    }

    @Test func countsAndKindFilters() throws {
        let (m, _) = try seeded()
        #expect(m.counts == AnnotationCounts(notes: 2, highlights: 3, bookmarks: 1))
        #expect(AnnotationKindFilter.all.count(m.counts) == 6 && AnnotationKindFilter.highlights.count(m.counts) == 3)
        #expect(m.items.count == 6)
        m.kind = .notes;      #expect(m.items.allSatisfy { $0.kind == .note } && m.items.count == 2)
        m.kind = .bookmarks;  #expect(m.items.map(\.book) == [19])
        m.kind = .highlights; #expect(m.items.count == 3)
    }

    @Test func colorBookAndTextFilters() throws {
        let (m, _) = try seeded()
        m.kind = .highlights
        m.color = .yellow;    #expect(m.items.count == 2 && m.items.allSatisfy { $0.color == .yellow })
        m.kind = .all;        #expect(m.color == nil && m.items.count == 6)   // salir de Resaltados limpia el color
        m.book = 43;          #expect(m.items.count == 3 && m.items.allSatisfy { $0.book == 43 })
        m.book = nil
        m.text = "BIEN";      #expect(m.items.map(\.body) == ["Todo ayuda a bien"])   // sin distinguir mayúsculas
        m.text = "永生";       #expect(m.items.count == 1 && m.items[0].book == 43)   // chino
        m.text = "inexistente"; #expect(m.items.isEmpty && m.isFiltered)
        m.clearFilters();     #expect(m.items.count == 6 && !m.isFiltered)
    }

    @Test func sortOrders() throws {
        let (m, _) = try seeded()
        m.sort = .canonical
        #expect(m.items.map(\.book) == [1, 19, 43, 43, 43, 45])
        m.sort = .updated
        #expect(m.items.first?.kind == .bookmark && m.items.last?.updatedAt == 50 && zip(m.items, m.items.dropFirst()).allSatisfy { $0.updatedAt >= $1.updatedAt })
    }

    @Test func refreshAfterMutation() throws {
        let (m, s) = try seeded()
        var mutations = 0; m.onMutation = { mutations += 1 }
        try s.addNote(book: 2, chapter: 1, verseStart: 1, body: "nueva")   // cambio externo
        #expect(m.items.count == 6)                                       // aún sin refrescar
        m.refresh(); #expect(m.items.count == 7 && m.counts.notes == 3)
        let note = try #require(m.items.first { $0.kind == .note && $0.book == 2 })
        m.delete(note)
        #expect(m.items.count == 6 && mutations == 1)
        let hl = try #require(m.items.first { $0.kind == .highlight && $0.book == 1 })
        s.lastUsedColor = .blue
        m.recolor(hl, to: .pink)
        #expect(m.items.first { $0.book == 1 }?.color == .pink && s.lastUsedColor == .blue)
        let bm = try #require(m.items.first { $0.kind == .bookmark })
        m.delete(bm); #expect(m.counts.bookmarks == 0 && mutations == 3)
    }

    @Test func appStateBumpsVersionOnAnnotationChanges() throws {
        let st = AppState(defaults: UserDefaults(suiteName: "v-\(UUID().uuidString)")!)
        st.user = try UserStore(path: NSTemporaryDirectory() + "v-\(UUID().uuidString).sqlite")
        let v0 = st.annotationVersion
        st.reloadAnnotations()
        #expect(st.annotationVersion == v0 + 1)
        // el editor de notas avisa al guardar → versión +1
        st.noteEditor.load(book: 43, chapter: 3, range: 16...16)
        st.noteEditor.edit("hola"); st.noteEditor.flush()
        #expect(st.annotationVersion == v0 + 2)
        st.annotationList.refresh()
        #expect(st.annotationList.counts.notes == 1)
        // beginNote crea una petición con libro/capítulo
        st.book = 45; st.chapter = 8
        st.beginNote(for: 28...29, selecting: 5)
        #expect(st.noteRequest.range == 28...29 && st.noteRequest.book == 45 && st.noteRequest.selecting == 5 && st.inspectorTab == .note)
    }
}
