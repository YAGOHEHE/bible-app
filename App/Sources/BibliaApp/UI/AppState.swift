import Foundation
import Observation
import AppKit

struct ScrollRequest: Equatable {
    var token: Int
    var verse: Int
}

/// Estado único de la app (@Observable, macOS 14).
@Observable
@MainActor
final class AppState {
    enum Load: Equatable { case loading, missingData, failed(String), ready }

    var load: Load = .loading
    var translations: [Translation] = []
    var translationId = "CUV"
    var bookNames: [BookName] = []
    var book = 43
    var chapter = 1
    var items: [DisplayVerse] = []
    var layout: [LayoutPiece] = []
    var selectedVerses: Set<Int> = [] { didSet { if selectedVerses.isEmpty { actionBarVisible = false } } }
    // Anotaciones (v1.1): por referencia, válidas en cualquier versión.
    var chapterAnnotations = ChapterAnnotations()
    var crossRefCounts: [Int: Int] = [:]
    var actionBarVisible = false
    /// Versículo junto al que se ancla la barra de acciones.
    var actionBarVerse = 1
    var inspectorTab: InspectorTab = .strong
    /// Rangos pedidos con «Anotar» / «Referencias» (los usan el editor y la lista de la tarea 5).
    var noteTarget: ClosedRange<Int>?
    /// Última petición de abrir el editor de notas (libro/capítulo incluidos: el lector puede cambiar de capítulo).
    var noteRequest = NoteRequest()
    var refsBook = 0
    var refsChapter = 0
    /// +1 con cada cambio de anotaciones (el panel «Notas» se refresca al observarlo).
    var annotationVersion = 0
    /// La barra lateral muestra el panel «Notas».
    var showNotesPanel = false
    var refsTarget: ClosedRange<Int>?
    var anchorVerse = 1
    var scrollRequest = ScrollRequest(token: 0, verse: 1)
    var recentBooks: [Int] = []
    var chapterCounts = [Int](repeating: 0, count: 66)
    var highlightedVerse: Int?
    /// Términos de la última búsqueda abierta: se resaltan en el texto del lector.
    var searchTerms: [String] = []
    /// Versículos destacados tras un salto (se desvanecen) y su opacidad actual (1...0).
    var flashVerses: Set<Int> = []
    var flashAlpha: Double = 0
    var showGoto = false
    var toast: String?
    // Vista paralela (S03) y gestor de versiones (S04)
    var parallelOn = false
    var parallelLayout: ParallelLayout = .columns
    var versionSet = VersionSet(order: [], enabled: [])
    var parallelColumns: [Translation] = []
    var parallelRows: [ParallelRow] = []
    var showVersions = false
    // Strong (S06) e historial (S07)
    var strongMode = false
    var showInspector = false
    var strongSpans: [Int: [StrongSpan]] = [:]
    var strongSelection: StrongSelection?
    var strongId: String?
    var strongWord: String?
    var strongEntry: LexiconEntry?
    var strongOccurrences: [StrongOccurrence] = []
    var strongOccurrenceTotal = 0
    var strongLoading = false
    var showHistory = false

    var bible: BibleDatabase?
    @ObservationIgnored var user: UserStore? {
        didSet {
            annotations = user.map { AnnotationStore(user: $0, defaults: defaults) }
            noteEditor.store = annotations
            annotationList.store = annotations
        }
    }
    @ObservationIgnored let noteEditor = NoteEditorModel()
    @ObservationIgnored let annotationList = AnnotationListModel()
    @ObservationIgnored private(set) var annotations: AnnotationStore?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var verseRepo: VerseRepository?
    @ObservationIgnored private var transRepo: TranslationRepository?
    @ObservationIgnored private var lastClickedVerse: Int?
    @ObservationIgnored private var tokenCounter = 0
    @ObservationIgnored private var flashTask: Task<Void, Never>?
    @ObservationIgnored let settings: AppSettings

    init(settings: AppSettings? = nil, defaults: UserDefaults = .standard) {
        self.settings = settings ?? AppSettings(defaults: defaults)
        self.defaults = defaults
        noteEditor.onChange = { [weak self] in self?.reloadAnnotations() }
        annotationList.onMutation = { [weak self] in self?.reloadAnnotations() }
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil,
                                               queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.noteEditor.flush() }
        }
    }

    // MARK: derived

    var nav: ChapterNav { ChapterNav(counts: chapterCounts) }
    var position: ChapterPosition { ChapterPosition(book: book, chapter: chapter) }
    var nextPosition: ChapterPosition? { nav.next(position) }
    var prevPosition: ChapterPosition? { nav.prev(position) }
    var canGoNext: Bool { nextPosition != nil }
    var canGoPrev: Bool { prevPosition != nil }
    var currentTranslation: Translation? { translations.first { $0.id == translationId } }
    var language: String { currentTranslation?.language ?? "es" }
    /// Idioma de los nombres de libro (CUVT: chino tradicional).
    var bookNameLanguage: String { BookNameLanguage.forTranslation(id: translationId, language: language) }
    var isLatin: Bool { language != "zh" }
    var chapterKey: String { "\(translationId)-\(book)-\(chapter)" }

    func bookName(_ n: Int) -> String {
        bookNames.first { $0.book == n }?.name ?? ReferenceParser.books[safe: n - 1]?.2 ?? "\(n)"
    }
    /// Nombre de libro en un idioma concreto (para copiar con referencia).
    func bookName(_ n: Int, language: String) -> String {
        guard let repo = transRepo,
              let names = try? repo.bookNames(language: language),
              let b = names.first(where: { $0.book == n }) else { return bookName(n) }
        return b.name
    }

    // MARK: bootstrap / resume (F01)

    func bootstrap() {
        guard load == .loading else { return }
        if user == nil { user = try? UserStore(path: UserStore.defaultURL().path) }
        do {
            try bootstrap(db: try BibleDatabase.openBundled())
        } catch BibleDatabaseError.notFound {
            load = .missingData
        } catch {
            load = .failed("\(error)")
        }
    }

    func bootstrap(db: BibleDatabase) throws {
        bible = db
        verseRepo = VerseRepository(db: db)
        let tr = TranslationRepository(db: db)
        transRepo = tr
        translations = try tr.all()
        chapterCounts = try tr.canonicalChapterCounts()
        recentBooks = ResumeState.loadRecents(from: defaults)

        let resume = ResumeState.load(from: defaults)
        var wanted = resume?.translation ?? settings.defaultTranslation
        if !translations.contains(where: { $0.id == wanted }) { wanted = translations.first?.id ?? wanted }
        translationId = wanted
        book = resume?.book ?? 43
        chapter = min(max(1, resume?.chapter ?? 1), max(1, chapterCounts[book - 1]))
        anchorVerse = resume?.verse ?? 1
        strongMode = defaults.bool(forKey: "strong.on")
        parallelOn = defaults.bool(forKey: "par.on")
        parallelLayout = ParallelLayout(rawValue: defaults.string(forKey: "par.layout") ?? "") ?? .columns
        versionSet = VersionSet.load(from: defaults, installed: translations.map(\.id), primary: translationId)
        try loadBookNames()
        load = .ready
        reloadChapter(scrollTo: anchorVerse)
        touchRecent()
    }

    private func loadBookNames() throws {
        guard let tr = transRepo else { return }
        bookNames = try tr.bookNames(language: bookNameLanguage)
    }

    func persist() {
        ResumeState(translation: translationId, book: book, chapter: chapter, verse: anchorVerse).save(to: defaults)
    }

    // MARK: chapter loading

    func reloadChapter(scrollTo verse: Int? = nil) {
        guard let repo = verseRepo else { return }
        do {
            let vs = try repo.chapter(translationId: translationId, book: book, chapter: chapter)
            let hs = try repo.headings(translationId: translationId, book: book, chapter: chapter)
            let ref = translationId == "KJV" ? nil :
                try repo.maxVerse(translationId: "KJV", book: book, chapter: chapter)
            items = ChapterBuilder.build(verses: vs, headings: hs, referenceMax: ref, translationId: translationId)
            layout = try repo.layout(translationId: translationId, book: book, chapter: chapter)
            try loadParallel(repo)
            try loadStrongSpans(repo)
            reloadAnnotations()
        } catch {
            load = .failed("\(error)")
            return
        }
        selectedVerses = []
        actionBarVisible = false
        lastClickedVerse = nil
        let target = verse ?? 1
        if parallelOn {
            anchorVerse = parallelRows.first(where: { $0.number >= target })?.number ?? parallelRows.first?.number ?? 1
        } else {
            anchorVerse = items.first(where: { $0.endNumber >= target })?.number ?? items.first?.number ?? 1
        }
        tokenCounter += 1
        scrollRequest = ScrollRequest(token: tokenCounter, verse: anchorVerse)
        persist()
    }

    private func loadParallel(_ repo: VerseRepository) throws {
        guard parallelOn else { parallelColumns = []; parallelRows = []; return }
        let cols = versionSet.columns(primary: translationId).compactMap { id in translations.first { $0.id == id } }
        parallelColumns = cols
        guard cols.count >= 2 else { parallelRows = []; return }
        let refMax = try repo.maxVerse(translationId: "KJV", book: book, chapter: chapter)
        let data: [ParallelColumnData] = try cols.map { t in
            let vs = try repo.chapter(translationId: t.id, book: book, chapter: chapter)
            let hs = try repo.headings(translationId: t.id, book: book, chapter: chapter)
            return ParallelColumnData(translationId: t.id, language: t.language,
                                      items: ChapterBuilder.build(verses: vs, headings: hs,
                                                                  referenceMax: t.id == "KJV" ? nil : refMax,
                                                                  translationId: t.id))
        }
        parallelRows = ParallelBuilder.build(book: book, chapter: chapter, columns: data)
    }

    // MARK: Strong (S06)

    /// Traducción con números Strong (KJV).
    var strongTranslationId: String? { translations.first(where: \.hasStrongs)?.id }
    /// Idioma de la versión con Strong (KJV -> "en"); los libros de las apariciones se nombran en él.
    var strongLanguage: String { translations.first(where: \.hasStrongs)?.language ?? "en" }

    /// Palabra abierta en el inspector con su contexto: (antes, palabra, después) recortado del versículo.
    var strongContext: (before: String, word: String, after: String, verse: Int)? {
        guard let sel = strongSelection, let sid = strongTranslationId,
              let span = strongSpans[sel.verse]?.first(where: { $0.start == sel.start }) else { return nil }
        var text: String?
        if translationId == sid { text = items.first { $0.number == sel.verse }?.text }
        else if let i = parallelColumns.firstIndex(where: { $0.id == sid }),
                case .verse(let v)? = parallelRows.first(where: { $0.number == sel.verse })?.cells[safe: i] { text = v.text }
        guard let t = text else { return nil }
        let chars = Array(t)
        guard span.end <= chars.count else { return nil }
        let lo = max(0, span.start - 40), hi = min(chars.count, span.end + 40)
        return ((lo > 0 ? "…" : "") + String(chars[lo..<span.start]), String(chars[span.start..<span.end]),
                String(chars[span.end..<hi]) + (hi < chars.count ? "…" : ""), sel.verse)
    }

    /// ¿Hay alguna versión con Strong a la vista (principal o columna paralela)?
    var strongAvailable: Bool {
        guard let id = strongTranslationId else { return false }
        return parallelOn ? parallelColumns.contains { $0.id == id } : translationId == id
    }

    private func loadStrongSpans(_ repo: VerseRepository) throws {
        strongSpans = [:]
        guard let id = strongTranslationId, strongAvailable else { return }
        let vs = try repo.chapter(translationId: id, book: book, chapter: chapter)
        let ws = try repo.words(translationId: id, book: book, chapter: chapter)
        strongSpans = StrongAligner.alignChapter(verses: vs, words: ws)
    }

    func setStrongMode(_ on: Bool) {
        strongMode = on && strongAvailable
        defaults.set(on, forKey: "strong.on")
    }
    func toggleStrongMode() { setStrongMode(!strongMode) }

    /// Resaltado para una versión: solo la que lleva Strong recibe tramos.
    func highlight(for translationId: String) -> TextHighlight {
        var h = TextHighlight(terms: searchTerms, flash: flashVerses, flashAlpha: flashAlpha)
        h.ann = chapterAnnotations
        if strongMode, translationId == strongTranslationId {
            h.strongSpans = strongSpans
            h.strongActive = strongSelection
        }
        return h
    }

    func openStrong(link url: URL) {
        guard let sel = StrongLink.parse(url) else { return }
        strongSelection = sel
        strongWord = strongSpans[sel.verse]?.first { $0.start == sel.start }?.word
        showStrong(sel.strong)
    }

    /// Abre el inspector con un número (p. ej. «G25»); `nil` = palabra sin número.
    func showStrong(_ id: String?) {
        showInspector = true
        inspectorTab = .strong
        strongId = id
        strongEntry = nil; strongOccurrences = []; strongOccurrenceTotal = 0
        guard let id, let db = bible else { strongLoading = false; return }
        strongLoading = true
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, self.strongId == id else { return }
            let repo = LexiconRepository(db: db)
            self.strongEntry = try? repo.entry(id)
            if let occ = try? repo.occurrences(strong: id, translationId: self.strongTranslationId ?? "KJV") {
                self.strongOccurrences = occ.items; self.strongOccurrenceTotal = occ.total
            }
            self.strongLoading = false
        }
    }

    func toggleInspector() { showInspector.toggle() }

    // MARK: historial (S07)

    func historyDays() -> [HistoryDay] {
        HistoryGrouping.group((try? user?.recentHistory(limit: 400)) ?? [])
    }

    func clearHistory() { try? user?.clearHistory() }

    func openHistory(_ e: HistoryEntry) {
        if e.translationId != translationId, translations.contains(where: { $0.id == e.translationId }) {
            setTranslation(e.translationId)
        }
        showHistory = false
        let v = e.verse
        open(ref: BibleRef(book: e.book, chapter: e.chapter, verseFrom: v, verseTo: v), record: false)
    }

    // MARK: parallel / version manager (S03, S04, F03, F08)

    func setParallel(_ on: Bool) {
        guard on != parallelOn else { return }
        parallelOn = on
        defaults.set(on, forKey: "par.on")
        reloadChapter(scrollTo: anchorVerse)
    }
    func toggleParallel() { setParallel(!parallelOn) }

    func setParallelLayout(_ l: ParallelLayout) {
        parallelLayout = l
        defaults.set(l.rawValue, forKey: "par.layout")
    }

    private func versionsChanged() {
        versionSet.save(to: defaults)
        if parallelOn { reloadChapter(scrollTo: anchorVerse) } else { parallelColumns = [] }
    }

    func setVersionEnabled(_ id: String, _ on: Bool) {
        guard id != translationId else { return }   // la principal siempre está activa
        if on { versionSet.enabled.insert(id) } else { versionSet.enabled.remove(id) }
        versionsChanged()
    }

    func moveVersions(from: IndexSet, to: Int) {
        versionSet.order.move(fromOffsets: from, toOffset: to)
        versionsChanged()
    }

    func moveVersion(_ id: String, by delta: Int) {
        guard let i = versionSet.order.firstIndex(of: id), versionSet.order.indices.contains(i + delta) else { return }
        versionSet.order.swapAt(i, i + delta)
        versionsChanged()
    }

    func setPrimary(_ id: String) {
        guard translations.contains(where: { $0.id == id }) else { return }
        versionSet.enabled.insert(id)
        versionSet.save(to: defaults)
        if id == translationId { versionsChanged() } else { setTranslation(id) }
    }

    var activeVersionCount: Int { versionSet.enabledCount(primary: translationId) }
    var parallelNumbers: [Int] { parallelRows.map(\.number) }

    private func touchRecent() {
        recentBooks = ResumeState.pushRecent(book, into: recentBooks)
        ResumeState.saveRecents(recentBooks, to: defaults)
    }

    private func record(kind: String, verse: Int? = nil) {
        try? user?.addHistory(translationId: translationId,
                              ref: BibleRef(book: book, chapter: chapter, verseFrom: verse, verseTo: verse), kind: kind)
    }

    // MARK: navigation (F02)

    func goNext() { if let p = nextPosition { move(to: p, kind: "page") } }
    func goPrev() { if let p = prevPosition { move(to: p, kind: "page") } }

    /// Selector (S02): salto a libro/capítulo.
    func jump(book b: Int, chapter c: Int = 1, verse: Int? = nil) {
        guard (1...66).contains(b) else { return }
        let maxC = chapterCounts[b - 1]
        move(to: ChapterPosition(book: b, chapter: min(max(1, c), max(1, maxC))), kind: "jump", verse: verse)
    }

    private func move(to p: ChapterPosition, kind: String, verse: Int? = nil) {
        guard p != position || verse != nil else { return }
        book = p.book; chapter = p.chapter
        reloadChapter(scrollTo: verse)
        touchRecent()
        record(kind: kind, verse: verse)
    }

    // MARK: ir a referencia (⌘L) y abrir resultados de búsqueda (F04, F05)

    enum GotoOutcome: Equatable {
        case went(BibleRef)
        case failed(GotoFailure)
    }

    /// Mensaje de error en línea para el campo "Ir a referencia".
    func gotoMessage(_ f: GotoFailure, input: String) -> String {
        switch f {
        case .notReference:
            return "No se reconoce «\(input.trimmingCharacters(in: .whitespaces))». Ejemplos: \(GotoResolver.examples)"
        case .chapterOutOfRange(let b, let m):
            return "\(bookName(b)) tiene \(m) capítulos."
        case .verseOutOfRange(let m):
            return "Este capítulo tiene \(m) versículos."
        }
    }

    /// Interpreta el texto, navega (historial 'jump'), desplaza al versículo y lo destaca.
    @discardableResult
    func goTo(_ text: String) -> GotoOutcome {
        switch GotoResolver.resolve(text, chapterCounts: chapterCounts) {
        case .failure(let f): return .failed(f)
        case .success(var ref):
            if let a = ref.verseFrom, let mx = try? verseRepo?.maxVerse(translationId: translationId, book: ref.book, chapter: ref.chapter) {
                if a > mx { return .failed(.verseOutOfRange(max: mx)) }
                ref.verseTo = min(ref.verseTo ?? a, mx)
            }
            searchTerms = []
            open(ref: ref)
            return .went(ref)
        }
    }

    /// Navega a la referencia y destaca sus versículos (si los tiene).
    func open(ref: BibleRef, record shouldRecord: Bool = true) {
        book = ref.book; chapter = ref.chapter
        reloadChapter(scrollTo: ref.verseFrom)
        touchRecent()
        if shouldRecord { record(kind: "jump", verse: ref.verseFrom) }
        if let a = ref.verseFrom { flash(verses: a...(ref.verseTo ?? a)) } else { clearFlash() }
    }

    /// Abre un resultado de búsqueda en la versión buscada, con las coincidencias resaltadas.
    func openHit(_ hit: SearchHit, terms: [String]) {
        if hit.translationId != translationId, translations.contains(where: { $0.id == hit.translationId }) {
            setTranslation(hit.translationId)
        }
        searchTerms = terms
        open(ref: BibleRef(book: hit.book, chapter: hit.chapter, verseFrom: hit.verse, verseTo: hit.verse))
    }

    func clearSearchHighlight() { searchTerms = [] }

    /// Destaca versículos ~3 s y los desvanece (sin animación gradual con "Reducir movimiento").
    func flash(verses: ClosedRange<Int>) {
        flashTask?.cancel()
        flashVerses = Set(verses)
        flashAlpha = 1
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        flashTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: reduce ? 3_000_000_000 : 2_400_000_000)
            if !reduce {
                for step in 1...6 {
                    if Task.isCancelled { return }
                    self?.flashAlpha = 1 - Double(step) / 6
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }
            }
            if Task.isCancelled { return }
            self?.clearFlash()
        }
    }

    func clearFlash() {
        flashTask?.cancel()
        flashVerses = []
        flashAlpha = 0
    }

    func setTranslation(_ id: String) {
        guard id != translationId, translations.contains(where: { $0.id == id }) else { return }
        versionSet.enabled.insert(id)
        versionSet.save(to: defaults)
        let keep = anchorVerse
        translationId = id
        try? loadBookNames()
        reloadChapter(scrollTo: keep)
    }

    /// El lector informa del versículo superior visible.
    func scrolled(toVerse v: Int) {
        guard v != anchorVerse else { return }
        anchorVerse = v
        persist()
    }

    func requestScroll(verse: Int) {
        tokenCounter += 1
        scrollRequest = ScrollRequest(token: tokenCounter, verse: verse)
    }

    // MARK: selection & copy (F10)

    func clickVerse(_ n: Int, shift: Bool, command: Bool) {
        if !flashVerses.isEmpty { clearFlash() }
        let nums = parallelOn ? parallelNumbers : items.map(\.number)
        if shift, let last = lastClickedVerse,
           let a = nums.firstIndex(of: last), let b = nums.firstIndex(of: n) {
            for i in min(a, b)...max(a, b) { selectedVerses.insert(nums[i]) }
        } else if command {
            if selectedVerses.contains(n) { selectedVerses.remove(n) } else { selectedVerses.insert(n) }
        } else if selectedVerses == [n] {
            selectedVerses = []
        } else {
            selectedVerses = [n]
        }
        lastClickedVerse = n
        if !selectedVerses.isEmpty { actionBarVerse = n; actionBarVisible = true }
    }

    func clearSelection() { selectedVerses = [] }

    var canCopyReference: Bool { !selectedVerses.isEmpty }

    func referenceText() -> String? {
        if parallelOn {
            return ParallelCopy.format(rows: parallelRows, selected: selectedVerses, book: book, chapter: chapter,
                                       columns: parallelColumns.map { ($0.id, $0.language) },
                                       bookName: { self.bookName($0, language: $1) })
        }
        let vs = items.filter { selectedVerses.contains($0.number) }
        guard !vs.isEmpty else { return nil }
        return CopyFormatter.format(verses: vs, bookName: bookName(book, language: bookNameLanguage), chapter: chapter,
                                    translationId: translationId, language: language)
    }

    func copyWithReference() {
        guard let s = referenceText() else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
        toast = "Copiado con referencia"
    }
}

enum InspectorTab: String, CaseIterable, Identifiable {
    case strong, note, refs
    var id: String { rawValue }
    var label: String { self == .strong ? "Strong" : self == .note ? "Nota" : "Referencias" }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
