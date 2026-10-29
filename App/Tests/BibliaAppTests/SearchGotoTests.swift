import Testing
import Foundation
@testable import BibliaApp

private let hasDB = BibleDatabase.bundledPath() != nil
private func openDB() throws -> BibleDatabase { try BibleDatabase(path: try #require(BibleDatabase.bundledPath())) }

private let counts: [Int] = {
    var c = [Int](repeating: 10, count: 66)
    c[18] = 150; c[42] = 21; c[44] = 16
    return c
}()

@Suite struct GotoResolverTests {
    private func ok(_ s: String) -> BibleRef? {
        if case .success(let r) = GotoResolver.resolve(s, chapterCounts: counts) { return r }
        return nil
    }

    @Test func spanishChineseEnglish() {
        #expect(ok("Juan 3:16") == BibleRef(book: 43, chapter: 3, verseFrom: 16, verseTo: 16))
        #expect(ok("约3:16") == BibleRef(book: 43, chapter: 3, verseFrom: 16, verseTo: 16))
        #expect(ok("John 3:16") == BibleRef(book: 43, chapter: 3, verseFrom: 16, verseTo: 16))
        #expect(ok("约翰福音3章16节") == BibleRef(book: 43, chapter: 3, verseFrom: 16, verseTo: 16))
        #expect(ok("约3：16") == BibleRef(book: 43, chapter: 3, verseFrom: 16, verseTo: 16))
    }

    @Test func rangesChapterOnlyAndBook() {
        #expect(ok("Rom 8:28-39") == BibleRef(book: 45, chapter: 8, verseFrom: 28, verseTo: 39))
        #expect(ok("Romanos 8:39-28") == BibleRef(book: 45, chapter: 8, verseFrom: 28, verseTo: 39))
        #expect(ok("Salmos 23") == BibleRef(book: 19, chapter: 23, verseFrom: nil, verseTo: nil))
        #expect(ok("诗篇23篇") == BibleRef(book: 19, chapter: 23, verseFrom: nil, verseTo: nil))
        #expect(ok("Juan") == BibleRef(book: 43, chapter: 1, verseFrom: nil, verseTo: nil))
    }

    @Test func invalid() {
        #expect(GotoResolver.resolve("amor eterno", chapterCounts: counts) == .failure(.notReference))
        #expect(GotoResolver.resolve("", chapterCounts: counts) == .failure(.notReference))
        #expect(GotoResolver.resolve("Foo 3:16", chapterCounts: counts) == .failure(.notReference))
        #expect(GotoResolver.resolve("Juan 99", chapterCounts: counts) == .failure(.chapterOutOfRange(book: 43, max: 21)))
        #expect(GotoResolver.resolve("Juan 0:1", chapterCounts: counts) == .failure(.chapterOutOfRange(book: 43, max: 21)))
    }

    @MainActor @Test(.enabled(if: hasDB)) func navigationRecordsJumpAndFlashes() throws {
        let suite = "goto-\(UUID().uuidString)"
        let d = try #require(UserDefaults(suiteName: suite))
        defer { d.removePersistentDomain(forName: suite) }
        let user = try UserStore(path: NSTemporaryDirectory() + "u-\(UUID().uuidString).sqlite")
        let st = AppState(settings: AppSettings(defaults: d), defaults: d)
        st.user = user
        try st.bootstrap(db: try openDB())

        #expect(st.goTo("约3:16") == .went(BibleRef(book: 43, chapter: 3, verseFrom: 16, verseTo: 16)))
        #expect(st.position == ChapterPosition(book: 43, chapter: 3))
        #expect(st.anchorVerse == 16 && st.flashVerses == [16] && st.flashAlpha == 1)
        let last = try #require(try user.recentHistory().first)
        #expect(last.kind == "jump" && last.verse == 16)

        _ = st.goTo("Rom 8:28-39")
        #expect(st.position == ChapterPosition(book: 45, chapter: 8))
        #expect(st.flashVerses == Set(28...39))

        _ = st.goTo("Salmos 23")
        #expect(st.position == ChapterPosition(book: 19, chapter: 23) && st.flashVerses.isEmpty)

        // inválidos: no navegan
        #expect(st.goTo("hola mundo") == .failed(.notReference))
        #expect(st.goTo("Juan 99") == .failed(.chapterOutOfRange(book: 43, max: 21)))
        #expect(st.goTo("Juan 3:999") == .failed(.verseOutOfRange(max: 36)))
        #expect(st.position == ChapterPosition(book: 19, chapter: 23))
        #expect(st.gotoMessage(.notReference, input: "hola mundo")
                == "No se reconoce «hola mundo». Ejemplos: Juan 3:16, 约3:16, John 3:16")

        // versículo final mayor que el máximo: se recorta
        #expect(st.goTo("Juan 3:30-99") == .went(BibleRef(book: 43, chapter: 3, verseFrom: 30, verseTo: 36)))
        st.clearFlash()
        #expect(st.flashVerses.isEmpty)
    }
}

@Suite struct SearchHighlightTests {
    private func strs(_ text: String, _ terms: [String]) -> [String] {
        SearchHighlighter.ranges(in: text, terms: terms).map { String(text[$0]) }
    }

    @Test func cjkCharacterLevel() {
        let t = "神爱世人，甚至将他的独生子赐给他们，叫一切信他的，不至灭亡，反得永生。"
        #expect(strs(t, ["永生"]) == ["永生"])
        #expect(strs(t, ["爱"]) == ["爱"])
        #expect(strs(t, ["他"]).count == 3)
        #expect(strs("永生永生", ["永生"]).count == 2)
    }

    @Test func latinCaseInsensitiveAndOr() {
        let t = "Porque de tal manera amó Dios al mundo; el Amor y la gracia"
        #expect(strs(t, ["amor"]) == ["Amor"])
        #expect(strs(t, ["amor", "gracia"]) == ["Amor", "gracia"])
        #expect(strs(t, ["xyz"]).isEmpty)
        // términos solapados se funden
        #expect(strs("abcdef", ["abcd", "cdef"]) == ["abcdef"])
    }

    @Test func windowKeepsMatchVisible() {
        let long = String(repeating: "palabra ", count: 60) + "AMOR" + String(repeating: " resto", count: 60)
        let w = SearchHighlighter.window(long, terms: ["amor"])
        #expect(w.count <= 152 && w.contains("AMOR") && w.hasPrefix("…") && w.hasSuffix("…"))
        #expect(SearchHighlighter.window("corto", terms: ["x"]) == "corto")
    }

    @Test func termsSplitOnSlash() {
        #expect(SearchTerms.split(" amor / gracia /") == ["amor", "gracia"])
        #expect(SearchTerms.split("/").isEmpty)
    }
}

@Suite struct SearchQueryTests {
    @Test(.enabled(if: hasDB)) func ftsAtLeastThreeChars() throws {
        let s = SearchRepository(db: try openDB())
        let hits = try s.search("loved the world", translationId: "KJV")
        #expect(hits.contains { $0.book == 43 && $0.chapter == 3 && $0.verse == 16 })
        #expect(hits.allSatisfy { $0.text.lowercased().contains("loved the world") })
        // sin distinguir mayúsculas
        let upper = try s.search("LOVED THE WORLD", translationId: "KJV")
        #expect(upper.count == hits.count)
    }

    @Test(.enabled(if: hasDB)) func likeForOneOrTwoChars() throws {
        let s = SearchRepository(db: try openDB())
        let a = try s.page("永生", translationId: "CUV")
        #expect(a.total > 20 && a.hits.contains { $0.book == 43 && $0.chapter == 3 && $0.verse == 16 })
        #expect(a.hits.allSatisfy { $0.text.contains("永生") })
        let b = try s.page("爱", translationId: "CUV", scope: .nt)
        #expect(b.total > 50 && b.hits.allSatisfy { $0.book >= 40 })
    }

    @Test(.enabled(if: hasDB)) func slashIsOr() throws {
        let s = SearchRepository(db: try openDB())
        let amor = try s.page("amor", translationId: "RV1909").total
        let gracia = try s.page("gracia", translationId: "RV1909").total
        let both = try s.page("amor/gracia", translationId: "RV1909")
        #expect(both.total >= max(amor, gracia) && both.total <= amor + gracia)
        #expect(both.hits.allSatisfy { $0.text.lowercased().contains("amor") || $0.text.lowercased().contains("gracia") })
        // OR con términos cortos (LIKE)
        let cjk = try s.page("永生/爱", translationId: "CUV")
        let only = try s.page("永生", translationId: "CUV").total
        #expect(cjk.total > only)
    }

    @Test(.enabled(if: hasDB)) func scopes() throws {
        let s = SearchRepository(db: try openDB())
        let all = try s.page("amor", translationId: "RV1909", limit: 5000)
        let ot = try s.page("amor", translationId: "RV1909", scope: .ot, limit: 5000)
        let nt = try s.page("amor", translationId: "RV1909", scope: .nt, limit: 5000)
        let john = try s.page("amor", translationId: "RV1909", scope: .book(43), limit: 5000)
        #expect(ot.hits.allSatisfy { $0.book <= 39 } && nt.hits.allSatisfy { $0.book >= 40 })
        #expect(ot.total + nt.total == all.total)
        #expect(!john.hits.isEmpty && john.hits.allSatisfy { $0.book == 43 })
        #expect(john.total == nt.perBook[43])
    }

    @Test(.enabled(if: hasDB)) func groupingCountsAndCap() throws {
        let s = SearchRepository(db: try openDB())
        let p = try s.page("amor", translationId: "RV1909", limit: 20)
        #expect(p.hits.count == 20 && p.total > 20)
        let groups = SearchGrouping.group(p.hits, totals: p.perBook)
        #expect(groups.map(\.book) == groups.map(\.book).sorted())
        #expect(groups.allSatisfy { $0.count == p.perBook[$0.book] })   // recuento real por libro
        #expect(p.perBook.values.reduce(0, +) == p.total)
        #expect(groups.map { $0.hits.count }.reduce(0, +) == 20)        // solo lo cargado
        #expect(p.hits.map(\.id) == p.hits.sorted { ($0.book, $0.chapter, $0.verse) < ($1.book, $1.chapter, $1.verse) }.map(\.id))
    }

    @Test(.enabled(if: hasDB)) func snippetAndHighlightOnRealVerse() throws {
        let s = SearchRepository(db: try openDB())
        let found = try s.search("永生", translationId: "CUV", scope: .book(43))
        let h = try #require(found.first { $0.chapter == 3 && $0.verse == 16 })
        #expect(h.snippet.contains("«永生»"))
        #expect(SearchHighlighter.ranges(in: h.text, terms: ["永生"]).count == 1)
    }

    @MainActor @Test(.enabled(if: hasDB)) func modelRunOpenAndNavigate() async throws {
        let suite = "sm-\(UUID().uuidString)"
        let d = try #require(UserDefaults(suiteName: suite))
        defer { d.removePersistentDomain(forName: suite) }
        let st = AppState(settings: AppSettings(defaults: d), defaults: d)
        st.user = try UserStore(path: NSTemporaryDirectory() + "u-\(UUID().uuidString).sqlite")
        try st.bootstrap(db: try openDB())
        st.setTranslation("CUV")
        let m = SearchModel(state: st)
        m.query = "永生"
        await m.run(record: true)
        #expect(m.phase == .results && m.total > 20 && m.terms == ["永生"])
        #expect(m.history == ["永生"])
        m.next()
        #expect(m.selected == 0 && st.searchTerms == ["永生"])
        let first = m.hits[0]
        #expect(st.position == ChapterPosition(book: first.book, chapter: first.chapter) && st.flashVerses == [first.verse])
        m.previous()
        #expect(m.selected == m.hits.count - 1)
        m.query = "zzzzqqq"
        await m.run()
        #expect(m.phase == .empty)
        m.query = "   "
        m.scheduleSearch()
        #expect(m.phase == .idle && m.hits.isEmpty)
    }
}

@Suite struct SearchHistoryTests {
    private func store() throws -> UserStore { try UserStore(path: NSTemporaryDirectory() + "u-\(UUID().uuidString).sqlite") }

    @Test func dedupeAndOrder() throws {
        let u = try store()
        let t0 = Date()
        try u.addSearch("amor", at: t0)
        try u.addSearch("gracia", at: t0 + 1)
        try u.addSearch("爱", at: t0 + 2)
        try u.addSearch("amor", at: t0 + 3)       // repetida: sube al principio, sin duplicar
        try u.addSearch("  ", at: t0 + 4)         // vacía: ignorada
        let r = try u.recentSearches()
        #expect(r == ["amor", "爱", "gracia"])
    }

    @Test func capAndClear() throws {
        let u = try store()
        let t0 = Date()
        for i in 0..<60 { try u.addSearch("q\(i)", at: t0 + Double(i)) }
        let r = try u.recentSearches()
        #expect(r.count == 50 && r.first == "q59" && r.last == "q10")
        try u.clearSearches()
        let e = try u.recentSearches()
        #expect(e.isEmpty)
    }
}
