import Testing
import AppKit
import Foundation
@testable import ClassicKit
@testable import BibliaCore

@Suite struct ParallelTests {
    static func dv(_ n: Int, _ text: String, end: Int? = nil) -> DisplayVerse {
        DisplayVerse(number: n, endNumber: end ?? n, text: text, headings: [])
    }
    static let long = String(repeating: "Porque de tal manera amó Dios al mundo. ", count: 6)
    static func sampleRows() -> [ParallelRow] {
        let a = dv(1, "短"), b = dv(2, "有一个法利赛人，名叫尼哥底母，是犹太人的官。"), c = dv(3, "三")
        return [
            ParallelRow(number: 1, cells: [.verse(a), .verse(dv(1, long)), .verse(dv(1, "In the beginning"))]),
            ParallelRow(number: 2, cells: [.verse(b), .missing, .verse(dv(2, long))]),
            ParallelRow(number: 3, cells: [.verse(c), .covered(by: dv(2, "x", end: 3)), .verse(dv(3, "three"))]),
        ]
    }
    static let cols: [(id: String, language: String)] = [("CUV", "zh"), ("RV1909", "es"), ("KJV", "en")]

    @Test func layoutDecision() {
        // 3 columnas necesitan >= 3*300+48 = 948 pt
        #expect(ParallelDecision.mode(on: false, layout: .columns, columnCount: 3, width: 2000) == .single)
        #expect(ParallelDecision.mode(on: true, layout: .columns, columnCount: 3, width: 948) == .columns)
        #expect(ParallelDecision.mode(on: true, layout: .columns, columnCount: 3, width: 947) == .glosses)
        #expect(ParallelDecision.mode(on: true, layout: .columns, columnCount: 2, width: 648) == .columns)
        #expect(ParallelDecision.mode(on: true, layout: .columns, columnCount: 2, width: 600) == .glosses)
        #expect(ParallelDecision.mode(on: true, layout: .interleaved, columnCount: 2, width: 3000) == .glosses)
        #expect(ParallelDecision.mode(on: true, layout: .columns, columnCount: 1, width: 3000) == .glosses)
    }

    @Test func versionManagerRules() {
        var s = VersionSet(order: ["CUV", "CUVT", "RV1909", "KJV"], enabled: ["CUV", "RV1909"])
        // principal CUV: no se puede apagar; mínimo 2 activadas
        #expect(!VersionManagerLogic.canToggleColumn(s, id: "CUV", primary: "CUV"))
        #expect(!VersionManagerLogic.canToggleColumn(s, id: "RV1909", primary: "CUV"))
        #expect(VersionManagerLogic.toggleColumn(&s, id: "KJV", primary: "CUV"))
        #expect(s.columns(primary: "CUV") == ["CUV", "RV1909", "KJV"])
        // máximo 3
        #expect(!VersionManagerLogic.toggleColumn(&s, id: "CUVT", primary: "CUV"))
        #expect(VersionManagerLogic.toggleColumn(&s, id: "RV1909", primary: "CUV"))
        #expect(s.columns(primary: "CUV") == ["CUV", "KJV"])
        // orden
        #expect(VersionManagerLogic.move(&s, id: "KJV", by: -1) && VersionManagerLogic.move(&s, id: "KJV", by: -1))
        #expect(s.order == ["CUV", "KJV", "CUVT", "RV1909"])
        #expect(!VersionManagerLogic.move(&s, id: "CUV", by: -1))
        #expect(!VersionManagerLogic.move(&s, id: "RV1909", by: 1))
    }

    @Test func prefsRoundTrip() {
        let d = UserDefaults(suiteName: "org.biblia.clasica.tests.\(UUID().uuidString)")!
        var p = ParallelPrefs.load(from: d, installed: ["CUV", "RV1909", "KJV"], primary: "CUV")
        #expect(!p.on && p.layout == .columns && p.glossesOn && p.glosses.ids.isEmpty)
        p.on = true; p.layout = .interleaved; p.glossesOn = false
        p.glosses = GlossSet(ids: ["KJV", "RV1909"])
        p.versions = VersionSet(order: ["KJV", "CUV", "RV1909"], enabled: ["CUV", "KJV"])
        p.save(to: d)
        let q = ParallelPrefs.load(from: d, installed: ["CUV", "RV1909", "KJV"], primary: "CUV")
        #expect(q.on && q.layout == .interleaved && !q.glossesOn)
        #expect(q.glosses.ids == ["KJV", "RV1909"])
        #expect(q.versions.order == ["KJV", "CUV", "RV1909"] && q.versions.enabled == ["CUV", "KJV"])
    }

    @Test func columnsAlignRowsAndMarkGaps() {
        let rows = Self.sampleRows()
        let bc = ColumnsAttributedBuilder.build(rows: rows, columns: Self.cols, palette: .light, fontScale: 1, innerWidth: 260)
        #expect(bc.columns.count == 3 && bc.rowNumbers == [1, 2, 3])
        #expect(bc.rowTops[0] == 0)
        for i in 1..<3 { #expect(abs(bc.rowTops[i] - (bc.rowTops[i - 1] + bc.rowHeights[i - 1])) < 0.001) }
        // la fila 1 toma la altura de la celda más alta (la española larga) y es mayor que la mínima
        #expect(bc.rowHeights[0] > bc.rowHeights[2])
        let es = bc.columns[1].text.string as NSString
        #expect(es.range(of: "—").location != NSNotFound)           // hueco
        let kjv = bc.columns[1].text.string
        #expect(kjv.contains("↑ (2–3)"))                             // cubierto por fusión
        // atributos de color: hueco atenuado
        let r = bc.columns[1].verseRanges[2]!
        let color = bc.columns[1].text.attribute(.foregroundColor, at: r.location + r.length - 1, effectiveRange: nil) as? NSColor
        #expect(color == ReaderPalette.light.textMuted)
        #expect(bc.row(atY: 0) == 1 && bc.row(atY: bc.rowTops[1] + 1) == 2 && bc.row(atY: 99999) == 3)
        #expect(bc.top(ofRow: 3) == bc.rowTops[2] && bc.top(ofRow: 99) == bc.rowTops[2])
        let sel = bc.rows(intersecting: [(1, NSRange(location: bc.columns[1].verseRanges[3]!.location, length: 2))])
        #expect(sel == [3])
    }

    /// El texto real de cada columna (NSTextView/TextKit) cae donde el constructor dice: filas alineadas.
    @Test func columnsMatchRealTextKitLayout() {
        let rows = Self.sampleRows()
        let inner: CGFloat = 220
        let bc = ColumnsAttributedBuilder.build(rows: rows, columns: Self.cols, palette: .light, fontScale: 1, innerWidth: inner)
        for c in bc.columns {
            let storage = NSTextStorage(attributedString: c.text)
            let lm = NSLayoutManager(), tc = NSTextContainer(containerSize: NSSize(width: inner, height: CGFloat.greatestFiniteMagnitude))
            tc.lineFragmentPadding = 0
            storage.addLayoutManager(lm); lm.addTextContainer(tc)
            lm.ensureLayout(for: tc)
            for (i, r) in rows.enumerated() {
                let range = c.verseRanges[r.number]!
                let g = lm.glyphIndexForCharacter(at: range.location)
                let y = lm.lineFragmentRect(forGlyphAt: g, effectiveRange: nil).minY
                #expect(abs(y - bc.rowTops[i]) < 0.6, "columna \(c.id) fila \(r.number): \(y) vs \(bc.rowTops[i])")
            }
            #expect(abs(lm.usedRect(for: tc).maxY - bc.totalHeight) < bc.rowHeights.last! )
        }
    }

    @Test func glossesBuilderRespectsPrimaryAndGlosses() {
        let rows = [
            ParallelRow(number: 1, cells: [.verse(Self.dv(1, "Primero")), .verse(Self.dv(1, "First")), .verse(Self.dv(1, "Primer"))]),
            ParallelRow(number: 2, cells: [.verse(Self.dv(2, "Segundo")), .missing, .covered(by: Self.dv(1, "x", end: 2))]),
            ParallelRow(number: 3, cells: [.missing, .verse(Self.dv(3, "Third")), .verse(Self.dv(3, "Tercero"))]),
        ]
        let items = [Self.dv(1, "Primero"), Self.dv(2, "Segundo")]
        let blocks = ChapterBuilder.blocks(items: items, layout: [], mode: .perVerse, showHeadings: true)
        let cols: [(id: String, language: String)] = [("RV1909", "es"), ("KJV", "en"), ("CUV", "zh")]
        let groups = GlossBuilder.groups(rows: rows, blocks: blocks, columns: cols)
        let style = ReaderStyle(palette: .light, fontScale: 1, latin: true, perVerse: true)
        let b = GlossAttributedBuilder.build(title: "Juan 3", groups: groups, style: style)
        let t = b.text.string
        #expect(t.contains("KJV\tFirst") && t.contains("CUV\tPrimer"))
        #expect(!t.contains("KJV\t\n") && t.contains("CUV\t(1–2)"))        // fusionado atenuado
        #expect(t.contains("3\u{2009}—"))                                  // la principal omite el 3: hueco
        // número de versículo una sola vez y sigla con color de acento de su versión
        let i = (t as NSString).range(of: "KJV").location
        #expect(b.text.attribute(.foregroundColor, at: i, effectiveRange: nil) as? NSColor == ReaderPalette.light.versionColor(1))
        let j = (t as NSString).range(of: "CUV").location
        #expect(b.text.attribute(.foregroundColor, at: j, effectiveRange: nil) as? NSColor == ReaderPalette.light.versionColor(2))
        // el rango del versículo 1 incluye sus glosas; las glosas llevan el versículo
        let r1 = b.verseRanges[1]!
        #expect(NSLocationInRange((t as NSString).range(of: "First").location, r1))
        #expect(b.verseRanges[2]!.location >= NSMaxRange(r1))
        // sin glosas: aviso con enlace
        let g0 = GlossBuilder.groups(rows: rows.map { ParallelRow(number: $0.number, cells: [$0.cells[0]]) }, blocks: blocks, columns: [cols[0]])
        let n = GlossAttributedBuilder.build(title: "Juan 3", groups: g0, style: style, notice: true)
        #expect(n.text.string.contains("Sin glosas") && n.text.string.contains("Elegir glosas"))
        var link: Any?
        n.text.enumerateAttribute(.link, in: NSRange(location: 0, length: n.text.length)) { v, _, _ in if v != nil { link = v } }
        #expect("\(link ?? "")" == "biblia://glosas")
    }

    @Test(.enabled(if: BibleDatabase.bundledPath() != nil, "bible.sqlite no presente"))
    func modelParallelStateAndPersistence() throws {
        let (m, s, _, nc) = try ModelTests.make()
        m.setTranslation("CUV")
        #expect(!m.parallel.on)
        #expect(m.columnIds.first == "CUV" && m.columnIds.count >= 2 && m.columnIds.count <= 3)
        m.jump(book: 19, chapter: 119)
        let ids = m.columnIds
        let rows = m.rows(for: ids)
        #expect(rows.count >= 176 && rows.count <= 176)               // Salmo 119: 176 filas
        #expect(rows.allSatisfy { $0.cells.count == ids.count })
        m.setParallel(on: true); m.setParallelLayout(.interleaved); m.setGlossesOn(false)
        #expect(m.toggleGloss("KJV") && m.toggleGloss("RV1909") && m.toggleGloss("CUVT"))
        #expect(!m.toggleGloss("WEB") || m.glossIds.count <= 3)
        #expect(m.glossIds.count <= 3 && !m.toggleGloss("CUV"))      // la principal no se puede elegir
        let again = ReaderModel(settings: s, user: nil, defaults: s.defaultsForTests, center: nc)
        try again.bootstrap(db: try BibleDatabase(path: try #require(BibleDatabase.bundledPath())))
        #expect(again.parallel.on && again.parallel.layout == .interleaved && !again.parallel.glossesOn)
        #expect(again.parallel.glosses.ids.prefix(3) == m.parallel.glosses.ids.prefix(3))
        // columnas con la principal primero, incluso si cambia
        again.setTranslation("KJV")
        #expect(again.columnIds.first == "KJV")
        #expect(!again.glossIds.contains("KJV"))
    }

    @Test(.enabled(if: BibleDatabase.bundledPath() != nil, "bible.sqlite no presente"))
    func psalm119ColumnsBuildFast() throws {
        let (m, _, _, _) = try ModelTests.make()
        m.jump(book: 19, chapter: 119)
        m.setVersionSet(VersionSet(order: m.parallel.versions.order, enabled: Set(["CUV", "RV1909", "KJV"])))
        let ids = m.columnIds
        let rows = m.rows(for: ids)
        let t0 = Date()
        let bc = ColumnsAttributedBuilder.build(rows: rows, columns: m.columnInfos(ids), palette: .light, fontScale: 1, innerWidth: 300)
        let dt = Date().timeIntervalSince(t0)
        #expect(bc.rowNumbers.count == 176)
        #expect(dt < 3, "Salmo 119 en columnas: \(dt) s")
    }
}
