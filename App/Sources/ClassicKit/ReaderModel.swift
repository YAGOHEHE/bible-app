import Foundation
import BibliaCore

/// Estado de lectura de «Biblia Clásica» (sin UI): versión, libro, capítulo, contenido, recientes, historial.
/// Todo en el hilo principal (sin concurrencia). Notifica con `NotificationCenter`.
public final class ReaderModel {
    public enum GotoOutcome: Equatable {
        case went(BibleRef)
        case failed(GotoFailure)
    }

    public let settings: ClassicSettings
    public private(set) var translations: [Translation] = []
    public private(set) var translationId = "CUV"
    public private(set) var book = 43
    public private(set) var chapter = 1
    public private(set) var bookNames: [BookName] = []
    public private(set) var chapterCounts = [Int](repeating: 0, count: 66)
    public private(set) var items: [DisplayVerse] = []
    public private(set) var layout: [LayoutPiece] = []
    public private(set) var recents: [Int] = []
    public private(set) var parallel = ParallelPrefs()
    private var itemsCache: [String: [DisplayVerse]] = [:]
    private var spanCache: [String: [Int: [StrongSpan]]] = [:]
    /// Términos de la búsqueda cuyo resultado se abrió: el lector los resalta en el capítulo mostrado.
    public private(set) var highlightTerms: [String] = []
    /// Versión en la que se buscó (el resaltado solo se pinta en sus columnas).
    public private(set) var highlightTranslation: String?
    /// Versículo superior visible (se persiste).
    public private(set) var anchorVerse = 1

    public private(set) var bible: BibleDatabase?
    private var verseRepo: VerseRepository?
    public var verseRepoForUI: VerseRepository? { verseRepo }
    public var userStoreForUI: UserStore? { user }
    private var transRepo: TranslationRepository?
    private let user: UserStore?
    private let defaults: UserDefaults
    private let center: NotificationCenter

    public init(settings: ClassicSettings, user: UserStore?, defaults: UserDefaults = .standard,
                center: NotificationCenter = .default) {
        self.settings = settings; self.user = user; self.defaults = defaults; self.center = center
    }

    // MARK: derived

    public var nav: ChapterNav { ChapterNav(counts: chapterCounts) }
    public var position: ChapterPosition { ChapterPosition(book: book, chapter: chapter) }
    public var currentTranslation: Translation? { translations.first { $0.id == translationId } }
    public var language: String { currentTranslation?.language ?? "es" }
    public var bookNameLanguage: String { BookNameLanguage.forTranslation(id: translationId, language: language) }
    public var isLatin: Bool { language != "zh" }
    public var canGoNext: Bool { nav.next(position) != nil }
    public var canGoPrev: Bool { nav.prev(position) != nil }

    public func bookName(_ n: Int) -> String {
        bookNames.first { $0.book == n }?.name ?? BookNameLanguage.name(n, language: bookNameLanguage)
    }

    /// Nombre de libro en un idioma concreto (para copiar con referencia).
    public func bookName(_ n: Int, language: String) -> String {
        guard let repo = transRepo, let names = try? repo.bookNames(language: language),
              let b = names.first(where: { $0.book == n }) else { return bookName(n) }
        return b.name
    }

    /// Nombre corto para menús: hasta el primer « (».
    public static func menuTitle(_ t: Translation) -> String {
        let short = t.name.components(separatedBy: " (").first ?? t.name
        return "\(t.id) · \(short)"
    }

    public var chapterTitle: String { "\(bookName(book)) \(chapter)" }

    public func blocks() -> [BookBlock] {
        ChapterBuilder.blocks(items: items, layout: layout,
                              mode: settings.layout == .paragraph ? .book : .perVerse,
                              showHeadings: settings.showHeadings)
    }

    // MARK: bootstrap / resume

    public func bootstrap(db: BibleDatabase) throws {
        bible = db
        verseRepo = VerseRepository(db: db)
        let tr = TranslationRepository(db: db)
        transRepo = tr
        translations = try tr.all()
        chapterCounts = try tr.canonicalChapterCounts()
        recents = ResumeState.loadRecents(from: defaults)
        let resume = ResumeState.load(from: defaults)
        var wanted = resume?.translation ?? settings.defaultTranslation
        if !translations.contains(where: { $0.id == wanted }) { wanted = translations.first?.id ?? wanted }
        translationId = wanted
        book = resume?.book ?? 43
        chapter = min(max(1, resume?.chapter ?? 3), max(1, chapterCounts[book - 1]))
        anchorVerse = resume?.verse ?? 1
        parallel = ParallelPrefs.load(from: defaults, installed: translations.map(\.id), primary: translationId)
        try loadBookNames()
        try reloadChapter()
        touchRecent()
    }

    private func loadBookNames() throws {
        guard let tr = transRepo else { return }
        bookNames = try tr.bookNames(language: bookNameLanguage)
    }

    public func persist() {
        ResumeState(translation: translationId, book: book, chapter: chapter, verse: anchorVerse).save(to: defaults)
    }

    private func loadItems(_ id: String) throws -> [DisplayVerse] {
        guard let repo = verseRepo else { return [] }
        let vs = try repo.chapter(translationId: id, book: book, chapter: chapter)
        let hs = try repo.headings(translationId: id, book: book, chapter: chapter)
        let ref = id == "KJV" ? nil : try repo.maxVerse(translationId: "KJV", book: book, chapter: chapter)
        return ChapterBuilder.build(verses: vs, headings: hs, referenceMax: ref, translationId: id)
    }

    private func reloadChapter() throws {
        guard let repo = verseRepo else { return }
        itemsCache = [:]
        spanCache = [:]
        items = try loadItems(translationId)
        itemsCache[translationId] = items
        layout = try repo.layout(translationId: translationId, book: book, chapter: chapter)
    }

    // MARK: parallel

    public var columnIds: [String] { parallel.versions.columns(primary: translationId) }
    public var glossIds: [String] { parallel.glosses.effective(primary: translationId, installed: translations.map(\.id)) }

    public func language(of id: String) -> String { translations.first { $0.id == id }?.language ?? "es" }
    public func columnInfos(_ ids: [String]) -> [(id: String, language: String)] { ids.map { ($0, language(of: $0)) } }

    /// Filas alineadas por versículo para las versiones `ids` del capítulo actual (la principal debe ir primero).
    public func rows(for ids: [String]) -> [ParallelRow] {
        let cols: [ParallelColumnData] = ids.map { id in
            if itemsCache[id] == nil { itemsCache[id] = (try? loadItems(id)) ?? [] }
            return ParallelColumnData(translationId: id, language: language(of: id), items: itemsCache[id] ?? [])
        }
        return ParallelBuilder.build(book: book, chapter: chapter, columns: cols)
    }

    private func parallelChanged() {
        parallel.save(to: defaults)
        center.post(name: .classicParallelChanged, object: self)
    }

    public func setParallel(on: Bool) { guard parallel.on != on else { return }; parallel.on = on; parallelChanged() }
    public func toggleParallel() { setParallel(on: !parallel.on) }
    public func setParallelLayout(_ l: ParallelLayout) { guard parallel.layout != l else { return }; parallel.layout = l; parallelChanged() }
    public func setVersionSet(_ v: VersionSet) {
        var n = v
        n.reconcile(installed: translations.map(\.id), primary: translationId)
        guard n != parallel.versions else { return }
        parallel.versions = n; parallelChanged()
    }
    public func setGlosses(_ g: GlossSet) { guard g != parallel.glosses else { return }; parallel.glosses = g; parallelChanged() }
    /// Marca/desmarca una glosa; false si no cabe (máx. 3) o es la principal.
    @discardableResult
    public func toggleGloss(_ id: String) -> Bool {
        var g = parallel.glosses
        let ok = g.toggle(id, primary: translationId)
        if ok { setGlosses(g) }
        return ok
    }
    public func setGlossesOn(_ v: Bool) { guard parallel.glossesOn != v else { return }; parallel.glossesOn = v; parallelChanged() }

    private func announce(scrollTo verse: Int?, flash: ClosedRange<Int>? = nil) {
        let target = verse ?? 1
        anchorVerse = items.first(where: { $0.endNumber >= target })?.number ?? items.first?.number ?? 1
        persist()
        var info: [String: Any] = ["scrollTo": anchorVerse]
        if let f = flash { info["flashFrom"] = f.lowerBound; info["flashTo"] = f.upperBound }
        center.post(name: .classicChapterChanged, object: self, userInfo: info)
    }

    /// Primera notificación tras abrir la ventana (el lector y la barra lateral se pintan con ella).
    public func announceInitial() { announce(scrollTo: anchorVerse) }

    // MARK: navigation

    public func goNext() { if let p = nav.next(position) { move(to: p, kind: "page") } }
    public func goPrev() { if let p = nav.prev(position) { move(to: p, kind: "page") } }

    public func jump(book b: Int, chapter c: Int = 1, verse: Int? = nil) {
        guard (1...66).contains(b) else { return }
        let maxC = chapterCounts[b - 1]
        move(to: ChapterPosition(book: b, chapter: min(max(1, c), max(1, maxC))), kind: "jump", verse: verse)
    }

    private func move(to p: ChapterPosition, kind: String, verse: Int? = nil, flash: ClosedRange<Int>? = nil) {
        guard p != position || verse != nil else { return }
        clearHighlight()
        book = p.book; chapter = p.chapter
        try? reloadChapter()
        touchRecent()
        try? user?.addHistory(translationId: translationId,
                              ref: BibleRef(book: book, chapter: chapter, verseFrom: verse, verseTo: verse), kind: kind)
        announce(scrollTo: verse, flash: flash)
    }

    public func gotoMessage(_ f: GotoFailure, input: String) -> String {
        switch f {
        case .notReference:
            return "No se reconoce «\(input.trimmingCharacters(in: .whitespaces))». Ejemplos: \(GotoResolver.examples)"
        case .chapterOutOfRange(let b, let m):
            return "\(bookName(b)) tiene \(m) capítulos."
        case .verseOutOfRange(let m):
            return "Este capítulo tiene \(m) versículos."
        }
    }

    /// Interpreta el texto (zh/zh-Hant/es/en), navega y pide destacar el versículo.
    @discardableResult
    public func goTo(_ text: String) -> GotoOutcome {
        switch GotoResolver.resolve(text, chapterCounts: chapterCounts) {
        case .failure(let f): return .failed(f)
        case .success(var ref):
            if let a = ref.verseFrom,
               let mx = try? verseRepo?.maxVerse(translationId: translationId, book: ref.book, chapter: ref.chapter) {
                if a > mx { return .failed(.verseOutOfRange(max: mx)) }
                ref.verseTo = min(ref.verseTo ?? a, mx)
            }
            let flash: ClosedRange<Int>? = ref.verseFrom.map { $0...(ref.verseTo ?? $0) }
            clearHighlight()
            // Misma regla que la app moderna: siempre recarga (puede ser el mismo capítulo).
            book = ref.book; chapter = ref.chapter
            try? reloadChapter()
            touchRecent()
            try? user?.addHistory(translationId: translationId, ref: ref, kind: "jump")
            announce(scrollTo: ref.verseFrom, flash: flash)
            return .went(ref)
        }
    }

    public func setTranslation(_ id: String) {
        guard id != translationId, translations.contains(where: { $0.id == id }) else { return }
        clearHighlight()
        let keep = anchorVerse
        translationId = id
        parallel.versions.reconcile(installed: translations.map(\.id), primary: id)
        parallel.save(to: defaults)
        try? loadBookNames()
        try? reloadChapter()
        center.post(name: .classicTranslationChanged, object: self)
        announce(scrollTo: keep)
    }

    private func clearHighlight() { highlightTerms = []; highlightTranslation = nil }

    /// Abre un versículo (resultado de búsqueda, historial, referencia cruzada, aparición Strong…).
    /// - `translation`: cambia antes a esa versión (nil = la actual). `terms`: resaltado de búsqueda.
    /// - `record`: añade una fila «Salto» al historial (false al volver desde el propio historial).
    /// Devuelve false si el libro/capítulo no existe.
    @discardableResult
    public func navigate(to ref: BibleRef, translation: String? = nil, terms: [String] = [], record: Bool = true) -> Bool {
        guard (1...66).contains(ref.book), ref.chapter >= 1, ref.chapter <= max(1, chapterCounts[ref.book - 1]) else { return false }
        if let t = translation, t != translationId, translations.contains(where: { $0.id == t }) { setTranslation(t) }
        var ref = ref
        if let a = ref.verseFrom,
           let mx = try? verseRepo?.maxVerse(translationId: translationId, book: ref.book, chapter: ref.chapter), mx > 0 {
            let lo = min(a, mx)
            ref.verseFrom = lo
            ref.verseTo = min(max(ref.verseTo ?? a, lo), mx)
        }
        let flash: ClosedRange<Int>? = ref.verseFrom.map { $0...max($0, ref.verseTo ?? $0) }
        highlightTerms = terms
        highlightTranslation = terms.isEmpty ? nil : (translation ?? translationId)
        book = ref.book; chapter = ref.chapter
        try? reloadChapter()
        touchRecent()
        if record { try? user?.addHistory(translationId: translationId, ref: ref, kind: "jump") }
        announce(scrollTo: ref.verseFrom, flash: flash)
        return true
    }

    // MARK: Strong / textos

    /// Texto del versículo `verse` (número de fila) de la versión `id` en el capítulo mostrado.
    public func verseText(_ id: String, verse: Int) -> String? {
        if itemsCache[id] == nil { itemsCache[id] = (try? loadItems(id)) ?? [] }
        return itemsCache[id]?.first { $0.number == verse }?.text
    }

    public func hasStrongs(_ id: String) -> Bool { translations.first { $0.id == id }?.hasStrongs ?? false }

    /// Versiones con Strong que se muestran ahora (la principal y, en columnas, las columnas).
    public func strongTargets(columns: Bool) -> [String] {
        let ids = columns ? columnIds : [translationId]
        return ids.filter(hasStrongs)
    }

    /// Palabras etiquetadas de la versión `id` en el capítulo actual, por versículo (cacheado por capítulo).
    public func strongSpans(for id: String) -> [Int: [StrongSpan]] {
        if let c = spanCache[id] { return c }
        var out: [Int: [StrongSpan]] = [:]
        if hasStrongs(id), let repo = verseRepo,
           let vs = try? repo.chapter(translationId: id, book: book, chapter: chapter),
           let ws = try? repo.words(translationId: id, book: book, chapter: chapter) {
            out = StrongAligner.alignChapter(verses: vs, words: ws)
        }
        spanCache[id] = out
        return out
    }

    /// El lector informa del versículo superior visible.
    public func scrolled(toVerse v: Int) {
        guard v != anchorVerse else { return }
        anchorVerse = v
        persist()
    }

    private func touchRecent() {
        recents = ResumeState.pushRecent(book, into: recents)
        ResumeState.saveRecents(recents, to: defaults)
        center.post(name: .classicRecentsChanged, object: self)
    }
}

// MARK: - Datos para inspector / historial

public extension ReaderModel {
    /// Texto del destino de una referencia cruzada en la versión actual (nil = no existe en esta versión).
    func text(of ref: BibleRef) -> String? {
        guard let repo = verseRepoForUI, let a = ref.verseFrom else { return nil }
        let vs = (try? repo.verses(translationId: translationId, book: ref.book, chapter: ref.chapter, from: a, to: ref.verseTo ?? a)) ?? []
        return CrossRefList.join(vs.sorted { $0.verse < $1.verse }.map(\.text), language: language)
    }

    func historyEntries(limit: Int = 200) -> [HistoryEntry] { (try? userStoreForUI?.recentHistory(limit: limit)) ?? [] }
    func clearHistory() { try? userStoreForUI?.clearHistory() }

    /// Nombre del libro en el idioma de la versión `id` (para el historial, que mezcla versiones).
    func bookName(_ n: Int, translation id: String) -> String {
        bookName(n, language: BookNameLanguage.forTranslation(id: id, language: language(of: id)))
    }
}

public extension ReaderModel {
    func isLatinTranslation(_ id: String) -> Bool { language(of: id) != "zh" }
}
