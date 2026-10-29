import Testing
import Foundation
import GRDB
@testable import BibliaCore

@Suite struct AnnotationTests {
    func make() throws -> (UserStore, AnnotationStore) {
        let u = try UserStore(path: NSTemporaryDirectory() + "ann-\(UUID().uuidString).sqlite")
        let d = UserDefaults(suiteName: "ann-\(UUID().uuidString)")!
        return (u, AnnotationStore(user: u, defaults: d))
    }

    @Test func migrationV2PreservesV1() throws {
        let path = NSTemporaryDirectory() + "mig-\(UUID().uuidString).sqlite"
        let q = try DatabaseQueue(path: path)
        var m = DatabaseMigrator()
        m.registerMigration("v1") { db in
            try db.execute(sql: """
                CREATE TABLE history(id INTEGER PRIMARY KEY AUTOINCREMENT, translation_id TEXT NOT NULL,
                  book INTEGER NOT NULL, chapter INTEGER NOT NULL, verse INTEGER,
                  kind TEXT NOT NULL CHECK (kind IN ('page','jump')), at REAL NOT NULL);
                CREATE INDEX history_at ON history(at DESC);
                CREATE TABLE search_history(query TEXT PRIMARY KEY, at REAL NOT NULL);
                INSERT INTO history(translation_id,book,chapter,verse,kind,at) VALUES ('rv',1,1,NULL,'page',5);
                INSERT INTO search_history VALUES ('amor', 7);
                """)
        }
        try m.migrate(q)
        let u = try UserStore(path: path)
        #expect(try u.recentHistory().count == 1)
        #expect(try u.recentSearches() == ["amor"])
        let a = AnnotationStore(user: u, defaults: UserDefaults(suiteName: UUID().uuidString)!)
        try a.setHighlight(.blue, book: 1, chapter: 1, verses: [1])
        #expect(try a.counts().highlights == 1)
    }

    @Test func highlights() throws {
        let (_, a) = try make()
        try a.setHighlight(.yellow, book: 43, chapter: 3, verses: [16, 17, 18])
        try a.setHighlight(.green, ref: BibleRef(book: 43, chapter: 3, verseFrom: 17, verseTo: 18))
        var c = try a.chapter(book: 43, chapter: 3)
        #expect(c.highlights == [16: .yellow, 17: .green, 18: .green])
        #expect(a.lastUsedColor == .green)
        try a.removeHighlight(book: 43, chapter: 3, verses: [16, 17])
        c = try a.chapter(book: 43, chapter: 3)
        #expect(c.highlights == [18: .green])
        #expect(try a.chapter(book: 43, chapter: 4).highlights.isEmpty)
    }

    @Test func bookmarks() throws {
        let (_, a) = try make()
        #expect(try a.toggleBookmark(book: 1, chapter: 1, verse: 3))
        #expect(try a.isBookmarked(book: 1, chapter: 1, verse: 3))
        #expect(try a.chapter(book: 1, chapter: 1).bookmarks == [3])
        #expect(try !a.toggleBookmark(book: 1, chapter: 1, verse: 3))
        #expect(try !a.isBookmarked(book: 1, chapter: 1, verse: 3))
    }

    @Test func notesCRUD() throws {
        let (_, a) = try make()
        let n = try #require(try a.addNote(book: 1, chapter: 1, verseStart: 2, verseEnd: 4, body: "  Hola\nsegunda línea "))
        #expect(n.range == 2...4)
        #expect(n.title == "Hola")
        #expect(try a.note(id: n.id)?.body == "Hola\nsegunda línea")
        let u = try #require(try a.updateNote(id: n.id, body: "Cambiada", at: n.updatedAt + 10))
        #expect(u.body == "Cambiada" && u.updatedAt == n.updatedAt + 10)
        #expect(try a.addNote(book: 1, chapter: 1, verseStart: 1, body: "   \n") == nil)
        #expect(try a.updateNote(id: n.id, body: "  ") == nil)
        #expect(try a.note(id: n.id) == nil)
        let m = try #require(try a.addNote(book: 1, chapter: 1, verseStart: 1, body: String(repeating: "x", count: 100)))
        #expect(m.title.count == 61)
        try a.deleteNote(id: m.id)
        #expect(try a.counts().notes == 0)
    }

    @Test func chapterOverlapAndMerged() throws {
        let (_, a) = try make()
        try a.addNote(book: 1, chapter: 1, verseStart: 2, verseEnd: 5, body: "A")
        try a.addNote(book: 1, chapter: 1, verseStart: 20, verseEnd: 20, body: "B")
        try a.setHighlight(.pink, book: 1, chapter: 1, verses: [21])
        try a.toggleBookmark(book: 1, chapter: 1, verse: 20)
        let c = try a.chapter(book: 1, chapter: 1)
        #expect(c.notes(overlapping: 4).map(\.body) == ["A"])
        #expect(c.notes(overlapping: 6).isEmpty)
        let d = c.forDisplayVerse(number: 20, end: 21)
        #expect(d.notes.map(\.body) == ["B"])
        #expect(d.color == .pink && d.isBookmarked && d.bookmarkedVerses == [20])
        #expect(c.forDisplayVerse(number: 3).notes.count == 1)
        #expect(c.forDisplayVerse(number: 10).isEmpty)
        #expect(c.forDisplayVerse(number: 4, end: 6).notes.count == 1)
    }

    @Test func listFiltersSortCounts() throws {
        let (_, a) = try make()
        try a.addNote(book: 43, chapter: 3, verseStart: 16, body: "Dios es amor", at: 100)
        try a.addNote(book: 1, chapter: 1, verseStart: 1, body: "神爱世人", at: 300)
        try a.addNote(book: 19, chapter: 23, verseStart: 1, body: "Pastor", at: 200)
        try a.setHighlight(.yellow, book: 43, chapter: 3, verses: [16], at: 150)
        try a.setHighlight(.blue, book: 1, chapter: 1, verses: [2, 3], at: 400)
        try a.toggleBookmark(book: 19, chapter: 23, verse: 1)
        #expect(try a.counts() == AnnotationCounts(notes: 3, highlights: 3, bookmarks: 1))
        #expect(try a.list().count == 7)
        #expect(try a.list(.init(kinds: [.note])).count == 3)
        #expect(try a.list(.init(kinds: [.bookmark])).count == 1)
        #expect(try a.list(.init(kinds: [.highlight], color: .blue)).count == 2)
        #expect(try a.list(.init(book: 43)).count == 2)
        #expect(try a.list(.init(text: "AMOR")).map(\.body) == ["Dios es amor"])
        #expect(try a.list(.init(text: "爱")).map(\.body) == ["神爱世人"])
        let canon = try a.list(.init(kinds: [.note]))
        #expect(canon.map(\.book) == [1, 19, 43])
        let upd = try a.list(.init(kinds: [.note], sort: .updated))
        #expect(upd.map(\.updatedAt) == [300, 200, 100])
    }

    @Test func performance() throws {
        let (_, a) = try make()
        for i in 0..<200 { try a.addNote(book: 1, chapter: i % 5 + 1, verseStart: i % 30 + 1, body: "n\(i)") }
        for i in 0..<200 { try a.setHighlight(.orange, book: 1, chapter: i % 5 + 1, verses: [i % 30 + 1]) }
        for i in 0..<100 { try a.toggleBookmark(book: 1, chapter: i % 5 + 1, verse: i % 30 + 1) }
        let t0 = Date()
        let c = try a.chapter(book: 1, chapter: 2)
        #expect(Date().timeIntervalSince(t0) < 0.02)
        #expect(!c.notes.isEmpty)
    }
}
