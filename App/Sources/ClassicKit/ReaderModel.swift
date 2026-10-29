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
    /// Versículo superior visible (se persiste).
    public private(set) var anchorVerse = 1

    public private(set) var bible: BibleDatabase?
    private var verseRepo: VerseRepository?
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

    private func reloadChapter() throws {
        guard let repo = verseRepo else { return }
        let vs = try repo.chapter(translationId: translationId, book: book, chapter: chapter)
        let hs = try repo.headings(translationId: translationId, book: book, chapter: chapter)
        let ref = translationId == "KJV" ? nil : try repo.maxVerse(translationId: "KJV", book: book, chapter: chapter)
        items = ChapterBuilder.build(verses: vs, headings: hs, referenceMax: ref, translationId: translationId)
        layout = try repo.layout(translationId: translationId, book: book, chapter: chapter)
    }

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
        let keep = anchorVerse
        translationId = id
        try? loadBookNames()
        try? reloadChapter()
        center.post(name: .classicTranslationChanged, object: self)
        announce(scrollTo: keep)
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
