import Testing
import Foundation
@testable import BibliaApp

private let hasDB = BibleDatabase.bundledPath() != nil

private func openDB() throws -> BibleDatabase { try BibleDatabase(path: try #require(BibleDatabase.bundledPath())) }

private func chapter(_ tr: String, _ book: Int, _ ch: Int) throws -> [DisplayVerse] {
    let db = try openDB()
    let repo = VerseRepository(db: db)
    let ref = tr == "KJV" ? nil : try repo.maxVerse(translationId: "KJV", book: book, chapter: ch)
    return ChapterBuilder.build(verses: try repo.chapter(translationId: tr, book: book, chapter: ch),
                                headings: try repo.headings(translationId: tr, book: book, chapter: ch),
                                referenceMax: ref)
}

@Suite struct ReaderTests {
    @Test(.enabled(if: hasDB)) func psalm3HasMultipleHeadingsOnVerse1() throws {
        let items = try chapter("CUV", 19, 3)
        let first = try #require(items.first)
        #expect(first.headings.count >= 2)
        #expect(first.headings[0] == "求助的晨祷")
        #expect(first.headings[1].hasPrefix("大卫逃避"))
    }

    @Test(.enabled(if: hasDB)) func rv1909HasNoHeadings() throws {
        let items = try chapter("RV1909", 43, 3)
        #expect(!items.isEmpty)
        #expect(items.allSatisfy { $0.headings.isEmpty })
    }

    @Test(.enabled(if: hasDB)) func mergedVerseLabelNumbers1() throws {
        let items = try chapter("CUV", 4, 1)
        let v20 = try #require(items.first { $0.number == 20 })
        #expect(v20.label == "20–21")
        #expect(!items.contains { $0.number == 21 })
        #expect(items.first { $0.number == 19 }?.label == "19")
    }

    @Test func mergedVerseLogicUnit() {
        func v(_ n: Int) -> Verse { Verse(translationId: "X", book: 1, chapter: 1, verse: n, text: "t\(n)") }
        let a = ChapterBuilder.build(verses: [v(1), v(2), v(4)], headings: [])
        #expect(a.map(\.label) == ["1", "2–3", "4"])
        // fusión al final del capítulo según versión de referencia
        let b = ChapterBuilder.build(verses: [v(1), v(2)], headings: [], referenceMax: 3)
        #expect(b.map(\.label) == ["1", "2–3"])
        // título de un versículo ausente pasa al que lo contiene
        let h = Heading(translationId: "X", book: 1, chapter: 1, verse: 3, text: "H")
        let c = ChapterBuilder.build(verses: [v(1), v(2), v(4)], headings: [h])
        #expect(c[1].headings == ["H"])
    }

    @Test(.enabled(if: hasDB)) func boundaryNavigation() throws {
        let counts = try TranslationRepository(db: try openDB()).canonicalChapterCounts()
        let nav = ChapterNav(counts: counts)
        #expect(counts[0] == 50)
        #expect(nav.next(ChapterPosition(book: 1, chapter: 50)) == ChapterPosition(book: 2, chapter: 1))
        #expect(nav.prev(ChapterPosition(book: 2, chapter: 1)) == ChapterPosition(book: 1, chapter: 50))
        #expect(nav.next(ChapterPosition(book: 66, chapter: 22)) == nil)
        #expect(nav.prev(ChapterPosition(book: 1, chapter: 1)) == nil)
        #expect(nav.next(ChapterPosition(book: 43, chapter: 3)) == ChapterPosition(book: 43, chapter: 4))
    }

    @Test func copyFormat() {
        let es = [DisplayVerse(number: 16, endNumber: 16, text: "Porque de tal manera amó Dios al mundo.", headings: [])]
        #expect(CopyFormatter.format(verses: es, bookName: "Juan", chapter: 3, translationId: "RV1909", language: "es")
                == "“Porque de tal manera amó Dios al mundo.” — Juan 3:16 (RV1909)")
        let zh = [DisplayVerse(number: 16, endNumber: 16, text: "神爱世人。", headings: []),
                  DisplayVerse(number: 17, endNumber: 17, text: "因为神差他的儿子。", headings: [])]
        #expect(CopyFormatter.format(verses: zh, bookName: "约翰福音", chapter: 3, translationId: "CUV", language: "zh")
                == "“神爱世人。因为神差他的儿子。” — 约翰福音 3:16–17 (CUV)")
        let en = [DisplayVerse(number: 16, endNumber: 16, text: "For God so loved", headings: []),
                  DisplayVerse(number: 18, endNumber: 18, text: "He that believeth", headings: [])]
        #expect(CopyFormatter.format(verses: en, bookName: "John", chapter: 3, translationId: "KJV", language: "en")
                == "“For God so loved He that believeth” — John 3:16, 18 (KJV)")
        let merged = [DisplayVerse(number: 20, endNumber: 21, text: "x", headings: [])]
        #expect(CopyFormatter.format(verses: merged, bookName: "Números", chapter: 1, translationId: "RV1909", language: "es").hasSuffix("Números 1:20–21 (RV1909)"))
    }

    @Test func resumeRoundTrip() throws {
        let suite = "resume-\(UUID().uuidString)"
        let d = try #require(UserDefaults(suiteName: suite))
        defer { d.removePersistentDomain(forName: suite) }
        #expect(ResumeState.load(from: d) == nil)
        let s = ResumeState(translation: "RV1909", book: 43, chapter: 3, verse: 16)
        s.save(to: d)
        #expect(ResumeState.load(from: d) == s)
        var r: [Int] = []
        for b in [1, 2, 3, 1, 4, 5, 6, 7, 8, 9, 10] { r = ResumeState.pushRecent(b, into: r) }
        #expect(r.count == 8 && r.first == 10)
        ResumeState.saveRecents(r, to: d)
        #expect(ResumeState.loadRecents(from: d) == r)
    }

    @Test func blockBuilderModes() {
        let items = (1...20).map { DisplayVerse(number: $0, endNumber: $0, text: "t", headings: $0 == 10 ? ["H"] : []) }
        #expect(BlockBuilder.build(items: items, paragraph: false, showHeadings: true).count == 20)
        let p = BlockBuilder.build(items: items, paragraph: true, showHeadings: true)
        #expect(p.map(\.id) == [1, 9, 10, 18])
        #expect(p.first { $0.id == 10 }?.headings == ["H"])
        #expect(BlockBuilder.build(items: items, paragraph: false, showHeadings: false).allSatisfy { $0.headings.isEmpty })
    }

    @MainActor @Test(.enabled(if: hasDB)) func appStateFlow() throws {
        let suite = "state-\(UUID().uuidString)"
        let d = try #require(UserDefaults(suiteName: suite))
        defer { d.removePersistentDomain(forName: suite) }
        let user = try UserStore(path: NSTemporaryDirectory() + "u-\(UUID().uuidString).sqlite")
        let st = AppState(settings: AppSettings(defaults: d), defaults: d)
        st.user = user
        try st.bootstrap(db: try openDB())
        st.setTranslation("RV1909")
        st.jump(book: 1, chapter: 50)
        st.goNext()
        #expect(st.position == ChapterPosition(book: 2, chapter: 1))
        st.jump(book: 66, chapter: 22)
        #expect(!st.canGoNext)
        let h = try user.recentHistory()
        #expect(h.map(\.kind) == ["jump", "page", "jump"])
        st.jump(book: 43, chapter: 3, verse: 16)
        st.clickVerse(16, shift: false, command: false)
        #expect(st.referenceText() == "“\(st.items.first { $0.number == 16 }!.text)” — Juan 3:16 (RV1909)")
        // reanudar
        let st2 = AppState(settings: AppSettings(defaults: d), defaults: d)
        try st2.bootstrap(db: try openDB())
        #expect(st2.position == ChapterPosition(book: 43, chapter: 3))
        #expect(st2.translationId == "RV1909")
        #expect(st2.anchorVerse == 16)
        // traducción sin el capítulo → lista vacía, sin romper
        st2.setTranslation("CUV")
        #expect(st2.translationId == "CUV" && st2.anchorVerse == 16)
    }
}
