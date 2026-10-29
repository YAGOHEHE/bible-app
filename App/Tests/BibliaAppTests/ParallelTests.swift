import Testing
@testable import BibliaApp
import Foundation
@testable import BibliaCore

private let hasDB = BibleDatabase.bundledPath() != nil

private func openDB() throws -> BibleDatabase { try BibleDatabase(path: try #require(BibleDatabase.bundledPath())) }

private func rows(_ ids: [String], _ book: Int, _ ch: Int) throws -> [ParallelRow] {
    let db = try openDB()
    let repo = VerseRepository(db: db)
    let ref = try repo.maxVerse(translationId: "KJV", book: book, chapter: ch)
    let langs = ["CUV": "zh", "RV1909": "es", "KJV": "en", "ASV": "en"]
    let cols = try ids.map { id in
        ParallelColumnData(translationId: id, language: langs[id]!,
                           items: ChapterBuilder.build(verses: try repo.chapter(translationId: id, book: book, chapter: ch),
                                                       headings: try repo.headings(translationId: id, book: book, chapter: ch),
                                                       referenceMax: id == "KJV" ? nil : ref))
    }
    return ParallelBuilder.build(book: book, chapter: ch, columns: cols)
}

@Suite struct ParallelTests {
    @Test(.enabled(if: hasDB)) func john3AllPresent() throws {
        let r = try rows(["CUV", "RV1909", "KJV"], 43, 3)
        #expect(r.count == 36)
        #expect(r.map(\.number) == Array(1...36))
        for row in r {
            for c in row.cells { if case .verse = c {} else { Issue.record("hueco en Juan 3:\(row.number)") } }
        }
    }

    @Test(.enabled(if: hasDB)) func numbers1_20MergedMarker() throws {
        let r = try rows(["CUV", "KJV"], 4, 1)
        let r20 = try #require(r.first { $0.number == 20 })
        let r21 = try #require(r.first { $0.number == 21 })
        guard case .verse(let v) = r20.cells[0] else { Issue.record("CUV 20 no es versículo"); return }
        #expect(v.label == "20–21")
        guard case .covered(let by) = r21.cells[0] else { Issue.record("CUV 21 debería estar cubierto"); return }
        #expect(by.label == "20–21")
        guard case .verse = r21.cells[1] else { Issue.record("KJV 21 falta"); return }
    }

    @Test(.enabled(if: hasDB)) func asvOmittedNTVerseIsDashNotMarker() throws {
        for (book, ch, v) in [(40, 17, 21), (44, 8, 37)] {
            let r = try rows(["KJV", "ASV"], book, ch)
            let row = try #require(r.first { $0.number == v })
            guard case .verse = row.cells[0] else { Issue.record("KJV \(book):\(ch):\(v) falta"); continue }
            #expect(row.cells[1] == .missing)
            // el versículo anterior de ASV no se etiqueta como fusión
            let prev = try #require(r.first { $0.number == v - 1 })
            if case .verse(let pv) = prev.cells[1] { #expect(pv.label == "\(v - 1)") } else { Issue.record("ASV anterior") }
        }
    }

    @Test(.enabled(if: hasDB)) func headingsPerColumn() throws {
        let r = try rows(["CUV", "RV1909", "ASV", "KJV"], 19, 3)
        func heads(_ cell: ParallelCell) -> [String] { if case .verse(let v) = cell { return v.headings }; return [] }
        let all = r.flatMap { $0.cells.enumerated().map { ($0.offset, heads($0.element)) } }
        #expect(all.filter { $0.0 == 0 }.contains { !$0.1.isEmpty })    // CUV
        #expect(all.filter { $0.0 == 1 }.allSatisfy { $0.1.isEmpty })   // RV1909 sin títulos
        #expect(all.filter { $0.0 == 2 }.contains { !$0.1.isEmpty })    // ASV
        #expect(all.filter { $0.0 == 3 }.contains { !$0.1.isEmpty })    // KJV
    }

    @Test func unitAlignmentAndCopy() {
        func v(_ n: Int, _ t: String, end e: Int? = nil) -> DisplayVerse {
            DisplayVerse(number: n, endNumber: e ?? n, text: t, headings: [])
        }
        let a = ParallelColumnData(translationId: "CUV", language: "zh", items: [v(1, "甲"), v(2, "乙", end: 3)])
        let b = ParallelColumnData(translationId: "RV1909", language: "es", items: [v(1, "uno"), v(3, "tres")])
        let r = ParallelBuilder.build(book: 1, chapter: 1, columns: [a, b])
        #expect(r.map(\.number) == [1, 2, 3])
        #expect(r[1].cells[1] == .missing)
        if case .covered(let by) = r[2].cells[0] { #expect(by.label == "2–3") } else { Issue.record("sin marcador") }
        let text = ParallelCopy.format(rows: r, selected: [1, 3], book: 1, chapter: 1,
                                       columns: [("CUV", "zh"), ("RV1909", "es")],
                                       bookName: { _, l in l == "zh" ? "创世记" : "Génesis" })
        #expect(text == "“甲乙” — 创世记 1:1–3 (CUV)\n“uno tres” — Génesis 1:1, 3 (RV1909)")
    }

    @Test(.enabled(if: hasDB)) func copyJohn316InThreeLanguages() throws {
        let r = try rows(["CUV", "RV1909", "KJV"], 43, 3)
        let t = try #require(ParallelCopy.format(rows: r, selected: [16], book: 43, chapter: 3,
                                                 columns: [("CUV", "zh"), ("RV1909", "es"), ("KJV", "en")],
                                                 bookName: { b, l in l == "zh" ? "约翰福音" : l == "es" ? "Juan" : "John" }))
        let lines = t.split(separator: "\n")
        #expect(lines.count == 3)
        #expect(lines[0].hasSuffix("约翰福音 3:16 (CUV)"))
        #expect(lines[1].hasSuffix("Juan 3:16 (RV1909)"))
        #expect(lines[2].hasSuffix("John 3:16 (KJV)"))
    }

    @Test func versionSetPersistsOrderAndEnabled() throws {
        let suite = "test.par.\(UUID().uuidString)"
        let d = try #require(UserDefaults(suiteName: suite))
        defer { d.removePersistentDomain(forName: suite) }
        let installed = ["CUV", "RV1909", "KJV", "ASV"]
        var s = VersionSet.load(from: d, installed: installed, primary: "CUV")
        #expect(s.columns(primary: "CUV") == ["CUV", "RV1909"])
        s.order = ["KJV", "CUV", "ASV", "RV1909"]
        s.enabled = ["CUV", "KJV", "RV1909"]
        s.save(to: d)
        let t = VersionSet.load(from: d, installed: installed, primary: "CUV")
        #expect(t.order == ["KJV", "CUV", "ASV", "RV1909"])
        #expect(t.columns(primary: "CUV") == ["CUV", "KJV", "RV1909"])
        #expect(t.columns(primary: "RV1909") == ["RV1909", "KJV", "CUV"])
    }

    @Test(.enabled(if: hasDB)) @MainActor func appStateRestoresParallel() throws {
        let suite = "test.par.state.\(UUID().uuidString)"
        let d = try #require(UserDefaults(suiteName: suite))
        defer { d.removePersistentDomain(forName: suite) }
        let a = AppState(settings: AppSettings(defaults: d), defaults: d)
        try a.bootstrap(db: try openDB())
        #expect(!a.parallelOn)
        a.setVersionEnabled("KJV", true)
        a.moveVersion("KJV", by: -1)
        a.setParallel(true)
        a.jump(book: 43, chapter: 3)
        #expect(a.parallelColumns.count == 3)
        #expect(a.parallelRows.count == 36)
        let b = AppState(settings: AppSettings(defaults: d), defaults: d)
        try b.bootstrap(db: try openDB())
        #expect(b.parallelOn)
        #expect(b.parallelColumns.map(\.id) == a.parallelColumns.map(\.id))
        #expect(b.versionSet.order == a.versionSet.order)
        #expect(b.book == 43 && b.chapter == 3)
    }
}
