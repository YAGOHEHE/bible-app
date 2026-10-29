import Testing
import Foundation
@testable import ClassicKit
@testable import BibliaCore

@Suite struct ModelTests {
    static func make() throws -> (ReaderModel, ClassicSettings, UserStore, NotificationCenter) {
        let d = UserDefaults(suiteName: "org.biblia.clasica.tests.\(UUID().uuidString)")!
        let nc = NotificationCenter()
        let s = ClassicSettings(defaults: d, center: nc)
        let u = try UserStore(path: NSTemporaryDirectory() + "u-\(UUID().uuidString).sqlite")
        let m = ReaderModel(settings: s, user: u, defaults: d, center: nc)
        try m.bootstrap(db: try BibleDatabase(path: try #require(BibleDatabase.bundledPath())))
        return (m, s, u, nc)
    }

    @Test(.enabled(if: BibleDatabase.bundledPath() != nil, "bible.sqlite no presente"))
    func navigationCrossesBooks() throws {
        let (m, _, u, _) = try Self.make()
        m.jump(book: 1, chapter: 50)
        m.goNext()
        #expect(m.position == ChapterPosition(book: 2, chapter: 1))
        m.goPrev()
        #expect(m.position == ChapterPosition(book: 1, chapter: 50))
        m.jump(book: 1, chapter: 1)
        #expect(!m.canGoPrev)
        #expect(m.recents.first == 1 && m.recents.count <= 8)
        #expect(try u.recentHistory().count >= 3)
    }

    @Test(.enabled(if: BibleDatabase.bundledPath() != nil, "bible.sqlite no presente"))
    func gotoAcceptsAllLanguagesAndFailsInline() throws {
        let (m, _, _, _) = try Self.make()
        for q in ["约3:16", "約3:16", "Juan 3:16", "John 3:16"] {
            m.jump(book: 1, chapter: 1)
            #expect(m.goTo(q) == .went(BibleRef(book: 43, chapter: 3, verseFrom: 16, verseTo: 16)), "\(q)")
            #expect(m.position == ChapterPosition(book: 43, chapter: 3))
        }
        if case .failed(.notReference) = m.goTo("zzz 99") {} else { Issue.record("debía fallar") }
        if case .failed(.chapterOutOfRange) = m.goTo("Juan 99") {} else { Issue.record("debía fallar") }
        if case .failed(.verseOutOfRange) = m.goTo("Juan 3:99") {} else { Issue.record("debía fallar") }
    }

    @Test(.enabled(if: BibleDatabase.bundledPath() != nil, "bible.sqlite no presente"))
    func translationBookNamesAndResume() throws {
        let (m, s, _, nc) = try Self.make()
        m.setTranslation("CUV"); #expect(m.bookName(43) == "约翰福音")
        m.setTranslation("CUVT"); #expect(m.bookName(43) == "約翰福音")
        m.setTranslation("RV1909"); #expect(m.bookName(43) == "S. Juan" || m.bookName(43).contains("Juan"))
        m.setTranslation("KJV"); #expect(m.bookName(43) == "John")
        #expect(m.translations.count == 8)
        // ancla y reanudación
        m.jump(book: 19, chapter: 23)
        m.scrolled(toVerse: 4)
        // el estado persistido es el de la instancia
        let again = ReaderModel(settings: s, user: nil, defaults: s.defaultsForTests, center: nc)
        try again.bootstrap(db: try BibleDatabase(path: try #require(BibleDatabase.bundledPath())))
        #expect(again.translationId == "KJV" && again.book == 19 && again.chapter == 23 && again.anchorVerse == 4)
    }

    @Test func settingsPersistAndClamp() {
        let d = UserDefaults(suiteName: "org.biblia.clasica.tests.\(UUID().uuidString)")!
        let nc = NotificationCenter()
        var fired = 0
        let tok = nc.addObserver(forName: .classicSettingsChanged, object: nil, queue: nil) { _ in fired += 1 }
        let s = ClassicSettings(defaults: d, center: nc)
        s.fontScale = 5; #expect(s.fontScale == 2.0)
        s.stepFont(-1); #expect(abs(s.fontScale - 1.9) < 1e-9)
        s.resetFont(); #expect(s.fontScale == 1.0)
        s.theme = .sepia; s.layout = .perLine; s.showHeadings = false
        let s2 = ClassicSettings(defaults: d, center: nc)
        #expect(s2.theme == .sepia && s2.layout == .perLine && !s2.showHeadings)
        #expect(fired >= 5)
        nc.removeObserver(tok)
    }
}
