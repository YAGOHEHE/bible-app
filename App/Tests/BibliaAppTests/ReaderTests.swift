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

    private func dv(_ n: Int, _ e: Int? = nil, heads: [String] = [], kinds: [String] = []) -> DisplayVerse {
        DisplayVerse(number: n, endNumber: e ?? n, text: "t\(n)", headings: heads, headingKinds: kinds)
    }
    private func lp(_ seq: Int, _ k: String, _ v: Int, _ t: String? = nil, level: Int = 1) -> LayoutPiece {
        LayoutPiece(seq: seq, kind: k, level: level, verse: v, text: t ?? "t\(v)")
    }

    @Test func blocksPerVerseMode() {
        let items = [dv(1), dv(2, heads: ["H"], kinds: ["s1"]), dv(3)]
        let b = ChapterBuilder.blocks(items: items, layout: [], mode: .perVerse, showHeadings: true)
        #expect(b.map(\.kind) == [.prose, .heading, .prose, .prose])
        #expect(ChapterBuilder.blocks(items: items, layout: [], mode: .perVerse, showHeadings: false).count == 3)
    }

    @Test func verseSplitBetweenProseAndPoetry() {
        // versículo 2 repartido: mitad en prosa, mitad en una línea q2
        let items = [dv(1), dv(2), dv(3)]
        let layout = [lp(1, "p", 1), lp(2, "+", 2, "t2a"), lp(3, "q", 2, "t2b", level: 2), lp(4, "q", 3, level: 1)]
        let b = ChapterBuilder.blocks(items: items, layout: layout, mode: .book, showHeadings: true)
        #expect(b.map(\.kind) == [.prose, .poetry, .poetry])
        #expect(b[0].pieces.map(\.verse) == [1, 2])
        #expect(b[0].pieces.map(\.label) == ["1", "2", nil].prefix(2).map { $0 })
        #expect(b[1].pieces.first?.verse == 2 && b[1].pieces.first?.label == nil)   // número solo en la 1ª aparición
        #expect(b[1].level == 2)
        #expect(b[2].pieces.first?.label == "3")
        #expect(b.allSatisfy { $0.contains(2) == ($0.id <= 1) })
    }

    @Test func mergedVerseAndHeadingOnAbsentVerse() {
        let v: (Int) -> Verse = { Verse(translationId: "X", book: 1, chapter: 1, verse: $0, text: "t\($0)") }
        // el verso 3 no existe (fusionado en 2): 2 se etiqueta "2–3" y el título del 3 cae en él
        let h = Heading(translationId: "X", book: 1, chapter: 1, verse: 3, text: "Título", kind: "s2")
        let items = ChapterBuilder.build(verses: [v(1), v(2), v(4)], headings: [h])
        #expect(items.map(\.label) == ["1", "2–3", "4"])
        #expect(items[1].headings == ["Título"] && items[1].headingKinds == ["s2"])
        let layout = [lp(1, "p", 1), lp(2, "+", 2), lp(3, "+", 4)]
        let b = ChapterBuilder.blocks(items: items, layout: layout, mode: .book, showHeadings: true)
        #expect(b.map(\.kind) == [.prose, .heading, .prose])      // el título parte el párrafo
        #expect(b[1].headingKind == "s2" && b[1].pieces.first?.text == "Título")
        #expect(b[2].pieces.first?.label == "2–3")
        #expect(b[2].pieces.last?.label == "4")
        #expect(ChapterBuilder.blockID(for: 3, in: b) == 1)         // 3 está dentro de 2–3; incluye el título
        #expect(ChapterBuilder.blockID(for: 1, in: b) == 0)
    }

    @Test func blankLinesBetweenStanzas() {
        let items = [dv(1), dv(2), dv(3)]
        let layout = [lp(1, "q", 1), lp(2, "q", 2), lp(3, "b", 2, ""), lp(4, "q", 3)]
        let b = ChapterBuilder.blocks(items: items, layout: layout, mode: .book, showHeadings: true)
        #expect(b.map(\.kind) == [.poetry, .poetry, .blank, .poetry])
    }

    @Test(.enabled(if: hasDB)) func realChaptersHaveStructure() throws {
        let db = try openDB()
        let repo = VerseRepository(db: db)
        func blocks(_ t: String, _ b: Int, _ c: Int) throws -> [BookBlock] {
            let items = try chapter(t, b, c)
            return ChapterBuilder.blocks(items: items, layout: try repo.layout(translationId: t, book: b, chapter: c),
                                         mode: .book, showHeadings: true)
        }
        for t in ["CUV", "KJV", "ASV", "RV1909"] {
            #expect(try blocks(t, 19, 23).filter { $0.kind == .poetry }.count >= 6, "Sal 23 \(t)")
            #expect(try blocks(t, 43, 3).filter { $0.kind == .prose }.count > 1, "Jn 3 \(t)")
        }
        // cada versículo del capítulo aparece en algún bloque
        let items = try chapter("CUV", 4, 1)
        let b = try blocks("CUV", 4, 1)
        #expect(items.allSatisfy { v in b.contains { $0.contains(v.number) } })
        #expect(b.flatMap(\.pieces).first { $0.verse == 20 }?.label == "20–21")
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
