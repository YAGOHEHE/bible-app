import Testing
import Foundation
@testable import BibliaCore

private let hasDB = BibleDatabase.bundledPath() != nil
private func openDB() throws -> BibleDatabase { try BibleDatabase(path: try #require(BibleDatabase.bundledPath())) }

private func word(_ idx: Int, _ w: String, _ s: String?) -> VerseWord {
    VerseWord(translationId: "KJV", book: 43, chapter: 3, verse: 16, idx: idx, word: w, strong: s)
}

@Suite struct StrongTests {
    @Test(.enabled(if: hasDB)) func john316Alignment() throws {
        let db = try openDB()
        let repo = VerseRepository(db: db)
        let vs = try repo.chapter(translationId: "KJV", book: 43, chapter: 3)
        let ws = try repo.words(translationId: "KJV", book: 43, chapter: 3)
        let spans = StrongAligner.alignChapter(verses: vs, words: ws)[16] ?? []
        let text = try #require(vs.first { $0.verse == 16 }).text
        func slice(_ s: StrongSpan) -> String {
            let a = text.index(text.startIndex, offsetBy: s.start), b = text.index(a, offsetBy: s.length)
            return String(text[a..<b])
        }
        let loved = try #require(spans.first { $0.strong == "G25" })
        #expect(slice(loved) == "loved")
        let world = try #require(spans.first { $0.strong == "G2889" })
        #expect(slice(world) == "the world")
        #expect(spans.count >= 20)
    }

    @Test func missingWordDoesNotBreakTheRest() {
        let text = "For God so loved the world."
        let spans = StrongAligner.align(text: text, words: [
            word(1, "God", "G2316"), word(2, "zzz", "G1"), word(3, "loved", "G25"), word(4, "so", nil)])
        #expect(spans.map(\.strong) == ["G2316", "G25"])
        #expect(spans[1].start == 11 && spans[1].length == 5)
    }

    @Test func linkRoundTrip() throws {
        let sp = StrongSpan(start: 12, length: 5, strong: "G25", word: "loved")
        let url = try #require(StrongLink.url(sp, verse: 16))
        #expect(StrongLink.parse(url) == StrongSelection(strong: "G25", verse: 16, start: 12))
    }

    @Test(.enabled(if: hasDB)) func lexiconLookupAndOccurrences() throws {
        let repo = LexiconRepository(db: try openDB())
        let g = try #require(try repo.entry("G25"))
        #expect(g.lemma == "ἀγαπάω")
        let h = try #require(try repo.entry("H430"))
        #expect(h.lemma?.unicodeScalars.first?.value == 0x05D0)
        let occ = try repo.occurrences(strong: "G25", translationId: "KJV", limit: 200)
        #expect(occ.total > 100)
        #expect(occ.items.count == min(200, occ.total))
        #expect(occ.items.first?.text.isEmpty == false)
    }

    @Test(.enabled(if: hasDB)) func cuvMatthew18NoPhantomMerge() throws {
        let repo = VerseRepository(db: try openDB())
        let vs = try repo.chapter(translationId: "CUV", book: 40, chapter: 18)
        let ref = try repo.maxVerse(translationId: "KJV", book: 40, chapter: 18)
        let items = ChapterBuilder.build(verses: vs, headings: [], referenceMax: ref, translationId: "CUV")
        #expect(items.first { $0.number == 10 }?.label == "10")
    }

    @Test func cuvRealMergeKept() {
        let v: (Int) -> Verse = { Verse(translationId: "CUV", book: 4, chapter: 1, verse: $0, text: "t") }
        let items = ChapterBuilder.build(verses: [v(19), v(20), v(22)], headings: [], translationId: "CUV")
        #expect(items.first { $0.number == 20 }?.label == "20–21")
    }
}

@Suite struct HistoryTests {
    private func e(_ id: Int64, _ b: Int, _ c: Int, _ v: Int?, at: Date, t: String = "CUV", kind: String = "page") -> HistoryEntry {
        HistoryEntry(id: id, translationId: t, book: b, chapter: c, verse: v, kind: kind, at: at.timeIntervalSince1970)
    }

    @Test func groupsByDayAndDedupes() {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let now = cal.date(from: DateComponents(year: 2026, month: 5, day: 10, hour: 12))!
        let h = { (d: Int, hour: Int) in cal.date(from: DateComponents(year: 2026, month: 5, day: d, hour: hour))! }
        let entries = [e(1, 43, 3, nil, at: h(10, 9)), e(2, 43, 3, nil, at: h(10, 10)), e(3, 43, 4, nil, at: h(10, 11)),
                       e(4, 19, 23, nil, at: h(9, 20)), e(5, 1, 1, nil, at: h(1, 8))]
        let days = HistoryGrouping.group(entries, now: now, calendar: cal)
        #expect(days.map(\.title).prefix(2) == ["Hoy", "Ayer"])
        #expect(days.count == 3)
        #expect(days[0].entries.map(\.id) == [3, 2])      // 1 y 2 iguales y consecutivos: queda la más reciente
        #expect(days[0].entries.count == 2)
    }

    @Test func storeAddReadClear() throws {
        let path = NSTemporaryDirectory() + "hist-\(UUID().uuidString).sqlite"
        defer { try? FileManager.default.removeItem(atPath: path) }
        let u = try UserStore(path: path)
        try u.addHistory(translationId: "KJV", ref: BibleRef(book: 43, chapter: 3, verseFrom: 16, verseTo: 16), kind: "jump")
        try u.addHistory(translationId: "KJV", ref: BibleRef(book: 43, chapter: 4), kind: "page")
        #expect(try u.recentHistory().count == 2)
        #expect(HistoryGrouping.group(try u.recentHistory()).first?.entries.first?.chapter == 4)
        try u.clearHistory()
        #expect(try u.recentHistory().isEmpty)
    }
}
