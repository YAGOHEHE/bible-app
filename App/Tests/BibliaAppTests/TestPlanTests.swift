import Testing
import Foundation
@testable import BibliaApp
@testable import BibliaCore

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

    /// BUG-001 (replica/bugs.md): el parser rechaza capítulo 0 y versículo 0.
    @Test func gotoRejectsChapterZero() {
        #expect(throws: (any Error).self) { try ReferenceParser.parse("John 0") }
        #expect(throws: (any Error).self) { try ReferenceParser.parse("John 0:1") }
        #expect(throws: (any Error).self) { try ReferenceParser.parse("John 3:0") }
        #expect(throws: (any Error).self) { try ReferenceParser.parse("John 3:1-0") }
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

@Suite struct BugfixTests {
    /// BUG-002: apilado cuando cada columna tendría < 300 pt según el ancho realmente disponible.
    @Test func parallelStackedFromAvailableWidth() {
        // 3 columnas: (w - 48 - 16) / 3 >= 300 => w >= 964
        #expect(ParallelMetrics.isStacked(availableWidth: 963, columns: 3, layout: .columns))
        #expect(!ParallelMetrics.isStacked(availableWidth: 964, columns: 3, layout: .columns))
        // 2 columnas: w >= 656
        #expect(ParallelMetrics.isStacked(availableWidth: 655, columns: 2, layout: .columns))
        #expect(!ParallelMetrics.isStacked(availableWidth: 656, columns: 2, layout: .columns))
        #expect(ParallelMetrics.isStacked(availableWidth: 2000, columns: 3, layout: .interleaved))
        // 800 de ventana - barra lateral 300 - inspector ~250 = 250 disponibles
        #expect(ParallelMetrics.isStacked(availableWidth: 250, columns: 3, layout: .columns))
    }

    /// BUG-005
    @Test func suggestionPicksBestOtherTranslation() {
        let counts: [(id: String, count: Int)] = [("KJV", 0), ("CUV", 149), ("RV1909", 3)]
        let s = SearchSuggestion.best(counts: counts, excluding: "KJV")
        #expect(s == SearchSuggestion(translationId: "CUV", count: 149))
        #expect(s?.message(query: "永生", current: "KJV") == "Sin resultados en KJV. «永生» aparece 149 veces en CUV")
        #expect(SearchSuggestion.best(counts: [("KJV", 0), ("CUV", 0)], excluding: "KJV") == nil)
        #expect(SearchSuggestion.best(counts: [("CUV", 5)], excluding: "CUV") == nil)
    }

    /// BUG-006
    @Test func occurrenceBookNamesFollowVersionLanguage() {
        #expect(BookNameLanguage.name(40, language: "en") == "Matthew")
        #expect(BookNameLanguage.name(40, language: "zh") == "马太福音")
        #expect(BookNameLanguage.name(40, language: "es") == "Mateo")
    }

    /// BUG-V11-03
    @Test func cuvtUsesTraditionalBookNames() {
        #expect(BookNameLanguage.forTranslation(id: "CUVT", language: "zh") == "zh-Hant")
        #expect(BookNameLanguage.forTranslation(id: "CUV", language: "zh") == "zh")
        #expect(BookNameLanguage.name(43, language: "zh-Hant") == "約翰福音")
        #expect(BookNameLanguage.name(66, language: "zh-Hant") == "啟示錄")
        #expect(ReferenceParser.traditional.count == 66)
    }

    @Test(.enabled(if: BibleDatabase.bundledPath() != nil, "bible.sqlite no presente"))
    func traditionalNamesInBundleMatchParser() throws {
        let db = try BibleDatabase(path: try #require(BibleDatabase.bundledPath()))
        let names = try TranslationRepository(db: db).bookNames(language: "zh-Hant")
        #expect(names.count == 66)
        for n in names { #expect(n.name == ReferenceParser.traditional[n.book - 1].0, "\(n.book)") }
    }
}
