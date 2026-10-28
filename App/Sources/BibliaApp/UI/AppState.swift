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
    var selectedVerses: Set<Int> = []
    var anchorVerse = 1
    var scrollRequest = ScrollRequest(token: 0, verse: 1)
    var recentBooks: [Int] = []
    var chapterCounts = [Int](repeating: 0, count: 66)
    var highlightedVerse: Int?
    var toast: String?
    // Vista paralela (S03) y gestor de versiones (S04)
    var parallelOn = false
    var parallelLayout: ParallelLayout = .columns
    var versionSet = VersionSet(order: [], enabled: [])
    var parallelColumns: [Translation] = []
    var parallelRows: [ParallelRow] = []
    var showVersions = false

    var bible: BibleDatabase?
    @ObservationIgnored var user: UserStore?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var verseRepo: VerseRepository?
    @ObservationIgnored private var transRepo: TranslationRepository?
    @ObservationIgnored private var lastClickedVerse: Int?
    @ObservationIgnored private var tokenCounter = 0
    @ObservationIgnored let settings: AppSettings

    init(settings: AppSettings? = nil, defaults: UserDefaults = .standard) {
        self.settings = settings ?? AppSettings(defaults: defaults)
        self.defaults = defaults
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
        bookNames = try tr.bookNames(language: language)
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
            items = ChapterBuilder.build(verses: vs, headings: hs, referenceMax: ref)
            try loadParallel(repo)
        } catch {
            load = .failed("\(error)")
            return
        }
        selectedVerses = []
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
                                                                  referenceMax: t.id == "KJV" ? nil : refMax))
        }
        parallelRows = ParallelBuilder.build(book: book, chapter: chapter, columns: data)
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

    private func record(kind: String) {
        try? user?.addHistory(translationId: translationId,
                              ref: BibleRef(book: book, chapter: chapter, verseFrom: nil, verseTo: nil), kind: kind)
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
        record(kind: kind)
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
        return CopyFormatter.format(verses: vs, bookName: bookName(book, language: language), chapter: chapter,
                                    translationId: translationId, language: language)
    }

    func copyWithReference() {
        guard let s = referenceText() else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
        toast = "Copiado con referencia"
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
