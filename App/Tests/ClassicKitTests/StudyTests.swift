import Testing
import Foundation
import AppKit
@testable import ClassicKit
@testable import BibliaCore

/// Doble de la base de datos para el controlador de búsqueda.
final class FakeProvider: SearchProviding {
    var delay: TimeInterval = 0
    var calls: [(String, String, Int)] = []
    var pages: [String: SearchPage] = [:]
    var failing = false
    private let lock = NSLock()
    func page(query: String, translationId: String, scope: SearchRepository.Scope, limit: Int) throws -> SearchPage {
        if delay > 0 { Thread.sleep(forTimeInterval: delay) }
        lock.lock(); calls.append((query, translationId, limit)); lock.unlock()
        if failing { throw NSError(domain: "x", code: 1, userInfo: [NSLocalizedDescriptionKey: "boom"]) }
        return pages[query] ?? SearchPage(hits: [], total: 0, perBook: [:])
    }
    func counts(query: String, scope: SearchRepository.Scope, translationIds: [String]) -> [(id: String, count: Int)] {
        translationIds.map { ($0, $0 == "CUV" ? 7 : 0) }
    }
    var callCount: Int { lock.lock(); defer { lock.unlock() }; return calls.count }
}

func hit(_ b: Int, _ c: Int, _ v: Int, t: String = "CUV", text: String = "texto") -> SearchHit {
    SearchHit(translationId: t, book: b, chapter: c, verse: v, snippet: text, text: text)
}

/// Espera (con tope) a que se cumpla la condición; las notificaciones llegan en la cola de retorno.
func wait(_ q: DispatchQueue, timeout: TimeInterval = 3, _ cond: @escaping () -> Bool) -> Bool {
    let end = Date().addingTimeInterval(timeout)
    while Date() < end {
        var ok = false
        q.sync { ok = cond() }
        if ok { return true }
        Thread.sleep(forTimeInterval: 0.01)
    }
    return false
}

@Suite struct SearchModelTests {
    func make(_ p: FakeProvider, debounce: TimeInterval = 0.05) -> (SearchModel, DispatchQueue) {
        let q = DispatchQueue(label: "test.cb")
        let m = SearchModel(provider: p, user: nil, translationId: "CUV", debounce: debounce,
                            workQueue: DispatchQueue(label: "test.work"), callbackQueue: q)
        m.allTranslationIds = ["CUV", "RV1909", "KJV"]
        return (m, q)
    }

    @Test func debounceCoalescesKeystrokes() {
        let p = FakeProvider()
        p.pages["gracia"] = SearchPage(hits: [hit(43, 1, 14)], total: 1, perBook: [43: 1])
        let (m, q) = make(p, debounce: 0.15)
        for s in ["g", "gr", "gra", "grac", "graci", "gracia"] { q.sync { m.queryChanged(s) } }
        #expect(wait(q) { m.results != nil })
        #expect(p.callCount == 1)
        #expect(p.calls[0].0 == "gracia")
    }

    @Test func staleResultsAreDiscarded() {
        let p = FakeProvider()
        p.delay = 0.15
        p.pages["aaa"] = SearchPage(hits: [hit(1, 1, 1, text: "aaa")], total: 1, perBook: [1: 1])
        p.pages["bbb"] = SearchPage(hits: [hit(2, 1, 1, text: "bbb")], total: 1, perBook: [2: 1])
        let (m, q) = make(p, debounce: 0.01)
        q.sync { m.submit("aaa") }                 // arranca la primera (lenta)
        Thread.sleep(forTimeInterval: 0.03)
        q.sync { m.submit("bbb") }                 // la segunda la deja obsoleta
        #expect(wait(q) { m.results?.query == "bbb" })
        Thread.sleep(forTimeInterval: 0.35)        // la primera ya terminó: no debe pisar el resultado
        q.sync { #expect(m.results?.query == "bbb") }
    }

    @Test func clearingQueryReturnsToIdleAndCancelsPending() {
        let p = FakeProvider()
        p.pages["abc"] = SearchPage(hits: [hit(1, 1, 1)], total: 1, perBook: [1: 1])
        let (m, q) = make(p, debounce: 0.05)
        q.sync { m.queryChanged("abc"); m.queryChanged("") }
        Thread.sleep(forTimeInterval: 0.2)
        q.sync { #expect(m.state == .idle) }
        #expect(p.callCount == 0)
    }

    @Test func emptySuggestsOtherTranslation() {
        let p = FakeProvider()
        let (m, q) = make(p)
        q.sync { m.submit("永生") }
        #expect(wait(q) { if case .empty = m.state { return true } else { return false } })
        q.sync {
            if case .empty(_, _, let s) = m.state { #expect(s == SearchSuggestion(translationId: "CUV", count: 7) || s == nil) }
        }
        // en RV1909 sí sugiere CUV
        q.sync { m.setTranslation("RV1909") }
        #expect(wait(q) { if case .empty(_, "RV1909", let s) = m.state { return s == SearchSuggestion(translationId: "CUV", count: 7) } else { return false } })
    }

    @Test func errorState() {
        let p = FakeProvider(); p.failing = true
        let (m, q) = make(p)
        q.sync { m.submit("abc") }
        #expect(wait(q) { if case .error(let e) = m.state { return e.contains("boom") } else { return false } })
    }

    @Test func nextPreviousWalkFlatHits() {
        let p = FakeProvider()
        p.pages["x"] = SearchPage(hits: [hit(1, 1, 1), hit(1, 2, 3), hit(2, 1, 1)], total: 3, perBook: [1: 2, 2: 1])
        let (m, q) = make(p)
        q.sync { m.submit("x") }
        #expect(wait(q) { m.results != nil })
        q.sync {
            #expect(m.advance(1)?.id == "CUV-1-1-1")
            #expect(m.advance(1)?.id == "CUV-1-2-3")
            #expect(m.advance(-1)?.id == "CUV-1-1-1")
            #expect(m.advance(-1) == nil)
            m.markActive(hit(2, 1, 1))
            #expect(m.advance(1) == nil)
        }
    }

    @Test func loadMoreGrowsLimit() {
        let p = FakeProvider()
        let many = (1...500).map { hit(1, 1, $0) }
        p.pages["x"] = SearchPage(hits: many, total: 700, perBook: [1: 700])
        let (m, q) = make(p)
        q.sync { m.submit("x") }
        #expect(wait(q) { m.results?.hasMore == true })
        q.sync { #expect(m.results?.remaining == 200); m.loadMore() }
        #expect(wait(q) { p.callCount == 2 })
        #expect(p.calls[1].2 == 1000)
    }

    @Test func historyDedupesAndCaps() throws {
        let u = try UserStore(path: NSTemporaryDirectory() + "u-\(UUID().uuidString).sqlite")
        let m = SearchModel(provider: FakeProvider(), user: u, translationId: "CUV", callbackQueue: DispatchQueue(label: "t"))
        for i in 0..<60 { m.submit("q\(i)"); Thread.sleep(forTimeInterval: 0.001) }
        m.submit("q10")
        let r = m.recentQueries()
        #expect(r.count == 50)
        #expect(r.first == "q10")
        #expect(r.filter { $0 == "q10" }.count == 1)
        m.clearHistory()
        #expect(m.recentQueries().isEmpty)
    }

    @Test func groupingRowsHaveHeadersCountsAndMore() {
        let r = SearchResults(query: "x", terms: ["x"], translationId: "CUV",
                              groups: SearchGrouping.group([hit(1, 1, 1), hit(1, 1, 2), hit(2, 1, 1)], totals: [1: 5, 2: 1]),
                              total: 6, loaded: 3)
        let rows = SearchRow.rows(r)
        #expect(rows.count == 6)           // 2 cabeceras + 3 resultados + «Mostrar más»
        #expect(rows[0] == .header(book: 1, count: 5))
        #expect(rows.last == .more(remaining: 3))
    }

    @Test func snippetHighlightsMatches() {
        let a = SearchSnippet.attributed(hit(43, 3, 16, text: "Porque de tal manera amó Dios al mundo"), terms: ["dios"],
                                         font: .systemFont(ofSize: 12), color: .black, matchBackground: .yellow, matchColor: .black)
        var ranges: [NSRange] = []
        a.enumerateAttribute(.backgroundColor, in: NSRange(location: 0, length: a.length)) { v, r, _ in if v != nil { ranges.append(r) } }
        #expect(ranges.count == 1)
        #expect((a.string as NSString).substring(with: ranges[0]).lowercased() == "dios")
    }
}

@Suite struct OverlayTests {
    @Test func strongSpansBecomeDottedLinks() throws {
        let text = "For God so loved the world"
        let words = [VerseWord(translationId: "KJV", book: 43, chapter: 3, verse: 16, idx: 0, word: "God", strong: "G2316"),
                     VerseWord(translationId: "KJV", book: 43, chapter: 3, verse: 16, idx: 1, word: "loved", strong: "G25")]
        let spans = StrongAligner.align(text: text, words: words)
        #expect(spans.count == 2)
        // texto maquetado: número + texto en dos «piezas» (poesía partida) con el mismo versículo
        let s = NSMutableAttributedString(string: "16 For God so\nloved the world")
        let r = NSRange(location: 0, length: s.length)
        let n = ReaderOverlays.applyStrong(to: s, ranges: [16: r], spans: [16: spans], verseText: { _ in text }, palette: .light)
        #expect(n == 2)
        let loc = (s.string as NSString).range(of: "loved").location
        let link = s.attribute(.link, at: loc, effectiveRange: nil) as? URL
        #expect(link != nil)
        #expect(StrongLink.parse(try #require(link))?.strong == "G25")
        let u = (s.attribute(.underlineStyle, at: loc, effectiveRange: nil) as? NSNumber)?.intValue ?? 0
        #expect(u & NSUnderlineStyle.patternDot.rawValue != 0)
        #expect(s.attribute(.underlineColor, at: loc, effectiveRange: nil) != nil)
        #expect(s.attribute(.link, at: 0, effectiveRange: nil) == nil)              // el «16» no
    }

    @Test func strongRespectsWordBoundariesAndSkipsMissing() {
        let spans = [StrongSpan(start: 0, length: 3, strong: "G1", word: "the"), StrongSpan(start: 8, length: 5, strong: "G2", word: "world")]
        let s = NSMutableAttributedString(string: "other the cold world")
        let n = ReaderOverlays.applyStrong(to: s, ranges: [1: NSRange(location: 0, length: s.length)], spans: [1: spans],
                                           verseText: { _ in "the zzz world" }, palette: .dark)
        #expect(n == 2)
        #expect(s.attribute(.link, at: 2, effectiveRange: nil) == nil)               // «other» contiene «the»: no cuenta
        #expect(s.attribute(.link, at: 6, effectiveRange: nil) != nil)               // «the» suelta sí
    }

    @Test func highlightMarksOnlyGivenVerses() {
        let s = NSMutableAttributedString(string: "永生神 永生")
        let n = ReaderOverlays.applyHighlight(to: s, ranges: [1: NSRange(location: 0, length: 3)], terms: ["永生"], palette: .light)
        #expect(n == 1)
        #expect(s.attribute(.backgroundColor, at: 0, effectiveRange: nil) != nil)
        #expect(s.attribute(.backgroundColor, at: 4, effectiveRange: nil) == nil)
    }
}

@Suite struct InspectorModelTests {
    @Test func contextMakesBoldWordWindow() throws {
        let t = "For God so loved the world, that he gave his only begotten Son, that whosoever believeth in him should not perish"
        let c = try #require(StrongContext.make(text: t, start: 11, length: 5, radius: 12))
        #expect(c.word == "loved")
        #expect(c.before.hasSuffix("so "))
        #expect(c.after.hasPrefix(" the world"))
        #expect(c.after.hasSuffix("…"))
    }

    @Test func linkRoundTrips() throws {
        let u = try #require(InspectorLink.url(BibleRef(book: 45, chapter: 5, verseFrom: 8, verseTo: 10), translation: "KJV"))
        let p = try #require(InspectorLink.parse(u))
        #expect(p.ref == BibleRef(book: 45, chapter: 5, verseFrom: 8, verseTo: 10))
        #expect(p.translation == "KJV")
        #expect(InspectorLink.parse("biblia://glosas") == nil)
        #expect(InspectorLink.isMore(InspectorLink.more))
    }

    @Test(.enabled(if: BibleDatabase.bundledPath() != nil, "bible.sqlite no presente"))
    func strongG25HasLemmaAnd109Occurrences() throws {
        let db = try BibleDatabase(path: try #require(BibleDatabase.bundledPath()))
        let m = StrongInspectorModel(lexicon: LexiconRepository(db: db))
        let text = "For God so loved the world, that he gave his only begotten Son"
        let c = try m.load(StrongSelection(strong: "G25", verse: 16, start: 11), word: "loved", verseText: text, length: 5,
                           translationId: "KJV", contextLabel: "John 3:16")
        #expect(c.entry?.lemma?.isEmpty == false)
        #expect(c.total == 109)
        #expect(c.occurrences.count == 109)
        #expect(!c.isHebrew)
        let a = StrongTextBuilder.build(c, palette: .light, bookName: { "B\($0)" })
        #expect(a.string.contains("G25"))
        #expect(a.string.contains("109 versículos"))
        #expect(a.string.contains("OTRAS APARICIONES · KJV"))
        // la palabra del contexto va en negrita
        let ctxAt = (a.string as NSString).range(of: "EN CONTEXTO").location
        let loc = (a.string as NSString).range(of: "loved", options: [], range: NSRange(location: ctxAt, length: a.length - ctxAt)).location
        let font = a.attribute(.font, at: loc, effectiveRange: nil) as? NSFont
        #expect(font.map { NSFontManager.shared.weight(of: $0) >= 9 } == true)
    }

    @Test(.enabled(if: BibleDatabase.bundledPath() != nil, "bible.sqlite no presente"))
    func hebrewEntryIsRTL() throws {
        let db = try BibleDatabase(path: try #require(BibleDatabase.bundledPath()))
        let m = StrongInspectorModel(lexicon: LexiconRepository(db: db))
        let c = try m.load(StrongSelection(strong: "H430", verse: 1, start: 0), word: "God", verseText: nil, length: 0,
                           translationId: "KJV", contextLabel: "Genesis 1:1")
        #expect(c.isHebrew)
        let a = StrongTextBuilder.build(c, palette: .light, bookName: { "B\($0)" })
        let lemma = c.entry?.lemma ?? ""
        let loc = (a.string as NSString).range(of: lemma).location
        let ps = a.attribute(.paragraphStyle, at: loc, effectiveRange: nil) as? NSParagraphStyle
        #expect(ps?.baseWritingDirection == .rightToLeft)
    }

    @Test(.enabled(if: BibleDatabase.bundledPath() != nil, "bible.sqlite no presente"))
    func johnThreeSixteenRefs() throws {
        let db = try BibleDatabase(path: try #require(BibleDatabase.bundledPath()))
        let m = RefsInspectorModel(repo: CrossRefRepository(db: db))
        let c = try m.load(book: 43, chapter: 3, verses: [16], bookName: { BookNameLanguage.name($0, language: "es") },
                           text: { $0.verseFrom == 8 ? nil : "texto" })
        #expect(c.total == 23)
        #expect(c.rows.first?.target.book == 45)
        #expect(c.rows.first?.target.chapter == 5 && c.rows.first?.target.verseFrom == 8)
        #expect(c.rows.first?.snippet == nil)                      // → «—»
        #expect(c.rows.dropFirst().first?.snippet == "texto")
        #expect(c.rows.map(\.votes) == c.rows.map(\.votes).sorted(by: >))
        #expect(c.header.hasSuffix("3:16"))
        let a = RefsTextBuilder.build(c, translationId: "RV1909", palette: .light)
        #expect(a.string.contains("23 referencias"))
        #expect(a.string.contains("—"))
        #expect(!c.hasMore)
    }

    @Test(.enabled(if: BibleDatabase.bundledPath() != nil, "bible.sqlite no presente"))
    func refsMergeSeveralVersesAndPage() throws {
        let db = try BibleDatabase(path: try #require(BibleDatabase.bundledPath()))
        let m = RefsInspectorModel(repo: CrossRefRepository(db: db))
        let one = try m.load(book: 43, chapter: 3, verses: [16], bookName: { "\($0)" }, text: { _ in "x" })
        let two = try m.load(book: 43, chapter: 3, verses: [16, 17, 16], bookName: { "\($0)" }, text: { _ in "x" }, limit: 5)
        #expect(two.total >= one.total)
        #expect(two.rows.count == 5 && two.hasMore)
        #expect(two.header.hasSuffix("3:16–17"))
        #expect(Set(two.rows.map(\.id)).count == 5)               // sin duplicados
    }
}

@Suite struct HistoryModelTests {
    @Test func groupsTodayYesterdayAndDate() throws {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func e(_ id: Int64, _ ago: TimeInterval, _ kind: String, _ t: String = "CUV", _ b: Int = 43, _ c: Int = 3, _ v: Int? = nil) -> HistoryEntry {
            HistoryEntry(id: id, translationId: t, book: b, chapter: c, verse: v, kind: kind, at: now.timeIntervalSince1970 - ago)
        }
        let entries = [e(5, 60, "page", "KJV", 43, 4), e(4, 3600, "jump", "RV1909", 43, 3, 16),
                       e(3, 86_400 + 60, "page"), e(2, 86_400 * 5, "jump", "CUV", 19, 23)]
        let s = HistoryModel.sections(entries, bookName: { t, b in "\(t):\(b)" }, now: now, calendar: cal)
        #expect(s.map(\.title).prefix(2) == ["Hoy", "Ayer"])
        #expect(s.count == 3)
        #expect(s[0].rows.count == 2)
        #expect(s[0].rows[0].label == "KJV:43 4")
        #expect(s[0].rows[1].label == "RV1909:43 3:16")
        #expect(s[0].rows[0].kind == "Pasar página" && s[0].rows[1].kind == "Salto")
        #expect(!s[0].rows[0].time.isEmpty)
        #expect(s[2].title.contains("2027") || s[2].title.contains("2026") || s[2].title.contains("2025") || !s[2].title.isEmpty)
    }

    @Test(.enabled(if: BibleDatabase.bundledPath() != nil, "bible.sqlite no presente"))
    func navigateFromHistoryDoesNotAddRow() throws {
        let (m, _, u, _) = try ModelTests.make()
        let before = try u.recentHistory().count
        #expect(m.navigate(to: BibleRef(book: 19, chapter: 23, verseFrom: nil, verseTo: nil), record: false))
        #expect(try u.recentHistory().count == before)
        #expect(m.position == ChapterPosition(book: 19, chapter: 23))
        #expect(m.navigate(to: BibleRef(book: 19, chapter: 24, verseFrom: 1, verseTo: 1)))
        #expect(try u.recentHistory().count == before + 1)
        #expect(m.historyEntries().count == before + 1)
        m.clearHistory()
        #expect(m.historyEntries().isEmpty)
        #expect(!m.navigate(to: BibleRef(book: 99, chapter: 1, verseFrom: nil, verseTo: nil)))
    }

    @Test(.enabled(if: BibleDatabase.bundledPath() != nil, "bible.sqlite no presente"))
    func searchOpenSetsHighlightAndClearsOnOtherMoves() throws {
        let (m, _, _, _) = try ModelTests.make()
        m.navigate(to: BibleRef(book: 43, chapter: 3, verseFrom: 16, verseTo: 16), translation: "KJV", terms: ["loved"])
        #expect(m.translationId == "KJV")
        #expect(m.highlightTerms == ["loved"] && m.highlightTranslation == "KJV")
        m.goNext()
        #expect(m.highlightTerms.isEmpty)
        #expect(m.hasStrongs("KJV") && !m.hasStrongs("CUV"))
        m.setTranslation("KJV")
        #expect(m.strongTargets(columns: false) == ["KJV"])
        m.jump(book: 43, chapter: 3)
        #expect(m.strongSpans(for: "KJV")[16]?.contains { $0.strong == "G25" } == true)
        #expect(m.text(of: BibleRef(book: 45, chapter: 5, verseFrom: 8, verseTo: 8))?.contains("commendeth") == true)
    }
}
