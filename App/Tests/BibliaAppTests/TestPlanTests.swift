import Testing
import Foundation
@testable import BibliaApp

/// Casos de replica/test-plan.md que no cubrían las suites de cada slice.
@Suite struct TestPlanTests {
    // F06 edge
    @Test func gotoChineseFullNameRange() throws {
        #expect(try ReferenceParser.parse("约翰福音3:16-18") == BibleRef(book: 43, chapter: 3, verseFrom: 16, verseTo: 18))
        #expect(try ReferenceParser.parse("  John 3:16  ").book == 43)
        #expect(try ReferenceParser.parse("JOHN 3:16") == BibleRef(book: 43, chapter: 3, verseFrom: 16, verseTo: 16))
    }
    @Test func gotoRejectsGarbage() {
        for bad in ["John 3:", "John :16", "😀", "   ", "John 3:16:1"] {
            #expect(throws: (any Error).self, "\(bad)") { try ReferenceParser.parse(bad) }
        }
    }

    /// BUG-001 (replica/bugs.md): el parser acepta capítulo 0. Quitar withKnownIssue al corregirlo.
    @Test func gotoRejectsChapterZero() {
        withKnownIssue("BUG-001") { #expect(throws: (any Error).self) { try ReferenceParser.parse("John 0") } }
    }

    @Test func resolverRejectsOutOfRangeChapters() {
        let counts = ReferenceParser.books.map { _ in 5 }
        for bad in ["John 0", "John 6", "John 0:1", "Foo 1"] {
            if case .success = GotoResolver.resolve(bad, chapterCounts: counts) { Issue.record("aceptó \(bad)") }
        }
        if case .failure = GotoResolver.resolve("John 5:3", chapterCounts: counts) { Issue.record("rechazó John 5:3") }
    }

    // F02 edge: extremos sin siguiente/anterior
    @Test func chapterNavExtremes() {
        let counts = ReferenceParser.books.map { _ in 3 }
        let nav = ChapterNav(counts: counts)
        #expect(nav.prev(ChapterPosition(book: 1, chapter: 1)) == nil)
        #expect(nav.next(ChapterPosition(book: 66, chapter: 3)) == nil)
        #expect(nav.next(ChapterPosition(book: 1, chapter: 3)) == ChapterPosition(book: 2, chapter: 1))
        #expect(nav.prev(ChapterPosition(book: 2, chapter: 1)) == ChapterPosition(book: 1, chapter: 3))
        #expect(nav.next(ChapterPosition(book: 99, chapter: 1)) == nil)
    }

    // F07 edge: tamaño extremo y persistencia
    @Test func fontScaleExtremes() {
        #expect(FontScale.clamp(0.0) == 0.8)
        #expect(FontScale.clamp(99) == 2.0)
        #expect(FontScale.clamp(-5) == 0.8)
        #expect(FontScale.clamp(1.04) == 1.0)
    }
    @MainActor @Test func settingsPersistAndSanitize() throws {
        let suite = "test.settings.\(UUID().uuidString)"
        let d = try #require(UserDefaults(suiteName: suite))
        defer { d.removePersistentDomain(forName: suite) }
        d.set(7.0, forKey: "set.fontScale")
        d.set("neon", forKey: "set.theme")
        let s = AppSettings(defaults: d)
        #expect(s.fontScale == 2.0)
        #expect(s.themeChoice == .system)
        s.themeChoice = .sepia
        s.stepFont(-1)
        let s2 = AppSettings(defaults: d)
        #expect(s2.themeChoice == .sepia)
        #expect(s2.fontScale == 1.9)
        s2.resetFont()
        #expect(s2.fontScale == 1.0)
        for _ in 0..<30 { s2.stepFont(-1) }
        #expect(s2.fontScale == 0.8)
    }

    // F08 edge: la principal siempre es columna; máximo 3; desinstalada se limpia
    @Test func versionSetEdges() {
        let vs = VersionSet(order: ["CUV", "RV1909", "KJV", "ASV"], enabled: ["CUV", "RV1909", "KJV", "ASV"])
        #expect(vs.columns(primary: "KJV") == ["KJV", "CUV", "RV1909"])
        #expect(vs.columns(primary: "ZZZ").count == 3)
        var gone = VersionSet(order: ["CUV", "OLD"], enabled: ["OLD"])
        gone.reconcile(installed: ["CUV", "KJV"], primary: "CUV")
        #expect(!gone.order.contains("OLD") && gone.order.contains("KJV"))
        #expect(gone.enabled.contains("CUV") && gone.enabled.count >= 2)
    }
}
