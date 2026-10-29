import Testing
@testable import BibliaApp
import Foundation
@testable import BibliaCore

private func tr(_ id: String, _ lang: String) -> Translation {
    Translation(id: id, name: id, language: lang, license: nil, sourceURL: nil, hasStrongs: false)
}
private func dv(_ n: Int, _ end: Int? = nil, _ text: String = "t") -> DisplayVerse {
    DisplayVerse(number: n, endNumber: end ?? n, text: text, headings: [])
}

@Suite struct GlossTests {
    @Test func maxThreeAndPrimaryExcluded() {
        var g = GlossSet()
        let a = g.toggle("CUV", primary: "CUV")
        let b = g.toggle("RV1909", primary: "CUV")
        let c = g.toggle("KJV", primary: "CUV")
        let d = g.toggle("ASV", primary: "CUV")
        let e = g.toggle("WEB", primary: "CUV")
        #expect(!a && b && c && d && !e)
        #expect(g.ids == ["RV1909", "KJV", "ASV"])
        let f = g.toggle("KJV", primary: "CUV")          // quitar
        #expect(f)
        #expect(g.ids == ["RV1909", "ASV"])
        // si la principal pasa a ser una glosa, se excluye sin perder el orden
        #expect(g.effective(primary: "RV1909") == ["ASV"])
        #expect(GlossSet(ids: ["A", "B", "C", "D", "A"]).effective(primary: "Z") == ["A", "B", "C"])
    }

    @Test func groupedByLanguageExcludesPrimary() {
        let ts = [tr("KJV", "en"), tr("CUV", "zh"), tr("RV1909", "es"), tr("ASV", "en")]
        let g = GlossSet.grouped(ts, primary: "CUV")
        #expect(g.map(\.language) == ["es", "en"])
        #expect(g[1].items.map(\.id) == ["KJV", "ASV"])
        #expect(GlossSet.grouped(ts, primary: "RV1909").map(\.language) == ["zh", "en"])
    }

    @Test func persistence() throws {
        let suite = "test.gloss.\(UUID().uuidString)"
        let d = try #require(UserDefaults(suiteName: suite))
        defer { d.removePersistentDomain(forName: suite) }
        #expect(GlossSet.load(from: d).ids.isEmpty)
        #expect(GlossSet.loadVisible(from: d))
        GlossSet(ids: ["KJV", "RV1909"]).save(to: d)
        GlossSet.saveVisible(false, to: d)
        #expect(GlossSet.load(from: d).ids == ["KJV", "RV1909"])
        #expect(!GlossSet.loadVisible(from: d))
    }

    private func rows() -> [ParallelRow] {
        [ParallelRow(number: 19, cells: [.verse(dv(19, nil, "a")), .verse(dv(19, nil, "b")), .verse(dv(19, nil, "c"))]),
         ParallelRow(number: 20, cells: [.verse(dv(20, nil, "a")), .verse(dv(20, 21, "b")), .missing]),
         ParallelRow(number: 21, cells: [.verse(dv(21, nil, "a")), .covered(by: dv(20, 21, "b")), .verse(dv(21, nil, "c"))])]
    }
    private let cols: [(id: String, language: String)] = [("CUV", "zh"), ("RV1909", "es"), ("KJV", "en")]
    private func blocks() -> [BookBlock] {
        let items = [dv(19, nil, "a"), dv(20, nil, "a"), dv(21, nil, "a")]
        return ChapterBuilder.blocks(items: items, layout: [], mode: .book, showHeadings: true)
    }

    @Test func missingHiddenMergedLabelled() {
        let g = GlossBuilder.groups(rows: rows(), blocks: blocks(), columns: cols)
        #expect(g.map(\.number) == [19, 20, 21])
        #expect(g[0].glosses.map(\.translationId) == ["RV1909", "KJV"])
        #expect(g[1].glosses.map(\.translationId) == ["RV1909"])        // KJV ausente: línea oculta
        #expect(g[2].glosses[0].content == .merged("20–21"))            // cubierto por fusión
        #expect(g[0].blocks.count == 1)
    }

    @Test func glossesHiddenLeavesPrimaryOnly() {
        let g = GlossBuilder.groups(rows: rows(), blocks: blocks(), columns: cols, showGlosses: false)
        #expect(g.allSatisfy { $0.glosses.isEmpty })
        #expect(g.count == 3)
    }

    @Test func primaryMissingVerseIsKeptWithGlosses() {
        let r = [ParallelRow(number: 5, cells: [.missing, .verse(dv(5, nil, "b"))])]
        let g = GlossBuilder.groups(rows: r, blocks: [], columns: Array(cols.prefix(2)))
        #expect(g.count == 1 && g[0].primaryMissing && g[0].glosses.count == 1)
        #expect(GlossBuilder.groups(rows: r, blocks: [], columns: Array(cols.prefix(2)), showGlosses: false).isEmpty)
    }

    @Test func poetryLinesStayInsideTheirVerse() {
        let items = [dv(1, nil, "x y"), dv(2, nil, "z")]
        let layout = [LayoutPiece(seq: 0, kind: "q", level: 1, verse: 1, text: "x"), LayoutPiece(seq: 1, kind: "q", level: 2, verse: 1, text: "y"),
                      LayoutPiece(seq: 2, kind: "q", level: 1, verse: 2, text: "z")]
        let bl = ChapterBuilder.blocks(items: items, layout: layout, mode: .book, showHeadings: true)
        let r = [ParallelRow(number: 1, cells: [.verse(items[0]), .verse(dv(1))]),
                 ParallelRow(number: 2, cells: [.verse(items[1]), .verse(dv(2))])]
        let g = GlossBuilder.groups(rows: r, blocks: bl, columns: Array(cols.prefix(2)))
        #expect(g[0].blocks.count == 2 && g[1].blocks.count == 1)
        #expect(g[0].blocks.allSatisfy { $0.kind == .poetry })
        #expect(g.flatMap(\.blocks).map(\.id) == [0, 1, 2])
    }

    @Test func copyIncludesPrimaryAndVisibleGlossesOnly() {
        let all = GlossBuilder.copyText(rows: rows(), selected: [19], book: 43, chapter: 3, columns: cols,
                                        showGlosses: true, bookName: { _, _ in "Juan" })
        #expect(all?.split(separator: "\n").count == 3)
        #expect(all?.contains("(CUV)") == true && all?.contains("(KJV)") == true)
        let only = GlossBuilder.copyText(rows: rows(), selected: [19], book: 43, chapter: 3, columns: cols,
                                         showGlosses: false, bookName: { _, _ in "Juan" })
        #expect(only?.split(separator: "\n").count == 1 && only?.contains("(CUV)") == true)
    }

    @Test func layoutDecision() {
        #expect(ParallelMetrics.isStacked(availableWidth: 2000, columns: 3, layout: .interleaved))
        #expect(!ParallelMetrics.isStacked(availableWidth: 1200, columns: 3, layout: .columns))
        #expect(ParallelMetrics.isStacked(availableWidth: 700, columns: 3, layout: .columns))   // cae a apilado (estilo glosas)
    }

    @Test func versionAccentsReadableAsText() {
        for p in [ThemePalette.light, .dark, .sepia] { #expect(p.versionAccent.count == 3) }
    }
}
