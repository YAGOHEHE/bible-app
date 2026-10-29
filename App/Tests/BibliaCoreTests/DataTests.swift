import Testing
import Foundation
@testable import BibliaCore

@Suite struct DataTests {
    @Test(.enabled(if: BibleDatabase.bundledPath() != nil, "bible.sqlite no presente"))
    func kjvJohn316() throws {
        let db = try BibleDatabase(path: try #require(BibleDatabase.bundledPath()))
        let vs = try VerseRepository(db: db).chapter(translationId: "KJV", book: 43, chapter: 3)
        let v16 = try #require(vs.first { $0.verse == 16 })
        #expect(v16.text.contains("loved the world"))
    }

    @Test func userStoreMigrationAndHistory() throws {
        let u = try UserStore(path: NSTemporaryDirectory() + "user-\(UUID().uuidString).sqlite")
        try u.addHistory(translationId: "KJV", ref: BibleRef(book: 43, chapter: 3, verseFrom: 16, verseTo: 16), kind: "jump")
        #expect(try u.recentHistory().count == 1)
        try u.addSearch("amor"); try u.addSearch("amor")
        #expect(try u.recentSearches() == ["amor"])
    }
}

@Suite struct SearchTests {
    @Test(.enabled(if: BibleDatabase.bundledPath() != nil, "bible.sqlite no presente"))
    func ftsAndLike() throws {
        let db = try BibleDatabase(path: try #require(BibleDatabase.bundledPath()))
        let s = SearchRepository(db: db)
        #expect(!(try s.search("loved the world", translationId: "KJV")).isEmpty)
        #expect(!(try s.search("永生", translationId: "CUV")).isEmpty)
        #expect(!(try s.search("爱", translationId: "CUV", scope: .nt)).isEmpty)
        #expect(!(try s.search("paz/amor", translationId: "RV1909", scope: .book(43))).isEmpty)
    }
}
