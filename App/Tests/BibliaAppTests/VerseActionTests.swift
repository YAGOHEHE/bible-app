import Testing
import Foundation
import SwiftUI
@testable import BibliaApp
@testable import BibliaCore

private let hasDB = BibleDatabase.bundledPath() != nil
private func openDB() throws -> BibleDatabase { try BibleDatabase(path: try #require(BibleDatabase.bundledPath())) }

@Suite struct VerseActionLogicTests {
    @Test func actionsDependOnSelectionAndTranslation() {
        var c = VerseActionContext(selectedCount: 0, strongAvailable: false, parallelOn: false)
        // sin selección nada está activo
        #expect(VerseAction.allCases.allSatisfy { !VerseActions.isEnabled($0, c) })
        // Strong solo se ofrece si hay una versión con Strong (KJV)
        #expect(!VerseActions.visible(c).contains(.strong))
        c.selectedCount = 1
        #expect(VerseActions.isEnabled(.copy, c) && VerseActions.isEnabled(.highlight, c))
        #expect(!VerseActions.isEnabled(.strong, c))
        c.strongAvailable = true
        #expect(VerseActions.isEnabled(.strong, c))
        // Comparar solo fuera de la paralela
        #expect(VerseActions.visible(c).contains(.compare))
        c.parallelOn = true
        #expect(!VerseActions.visible(c).contains(.compare))
        // sin base de usuario no se puede anotar, pero sí copiar
        c.annotationsAvailable = false
        #expect(!VerseActions.isEnabled(.highlight, c) && !VerseActions.isEnabled(.bookmark, c) && !VerseActions.isEnabled(.note, c))
        #expect(VerseActions.isEnabled(.copy, c) && VerseActions.isEnabled(.crossRefs, c))
    }

    @Test func menuEnablementMatchesContext() {
        // El menú «Versículo» usa isEnabled: ⌘C, ⌥⌘C, ⌥⌘H, ⌥⌘N y ⌘D exigen selección.
        let none = VerseActionContext()
        for a in [VerseAction.copy, .copyReference, .highlight, .note, .bookmark] {
            #expect(!VerseActions.isEnabled(a, none))
        }
        let one = VerseActionContext(selectedCount: 2, strongAvailable: false, parallelOn: false)
        for a in [VerseAction.copy, .copyReference, .highlight, .note, .bookmark] {
            #expect(VerseActions.isEnabled(a, one))
        }
    }

    @Test func mergedSelectionExpandsAndRange() {
        let items = [DisplayVerse(number: 19, endNumber: 19, text: "a", headings: []),
                     DisplayVerse(number: 20, endNumber: 21, text: "b", headings: []),
                     DisplayVerse(number: 22, endNumber: 22, text: "c", headings: [])]
        #expect(VerseActions.verses(selected: [20], items: items, parallel: false) == [20, 21])
        #expect(VerseActions.verses(selected: [19, 22], items: items, parallel: false) == [19, 22])
        #expect(VerseActions.verses(selected: [20], items: items, parallel: true) == [20])
        #expect(VerseActions.range(of: [22, 19, 20]) == 19...22)
        #expect(VerseActions.range(of: []) == nil)
    }

    @Test func plainCopyJoinsVerses() {
        let a = DisplayVerse(number: 16, endNumber: 16, text: " Porque de tal manera ", headings: [])
        let b = DisplayVerse(number: 17, endNumber: 17, text: "Dios no envió.", headings: [])
        #expect(PlainCopy.text(verses: [b, a], language: "es") == "Porque de tal manera Dios no envió.")
        #expect(PlainCopy.text(verses: [DisplayVerse(number: 1, endNumber: 1, text: "神爱", headings: []),
                                        DisplayVerse(number: 2, endNumber: 2, text: "世人", headings: [])], language: "zh") == "神爱世人")
        let rows = [ParallelRow(number: 16, cells: [.verse(a), .verse(DisplayVerse(number: 16, endNumber: 16, text: "For God", headings: []))]),
                    ParallelRow(number: 17, cells: [.verse(b), .missing])]
        let t = PlainCopy.text(rows: rows, selected: [16, 17], columns: [("RV1909", "es"), ("KJV", "en")])
        #expect(t == "Porque de tal manera Dios no envió.\nFor God")
        #expect(PlainCopy.text(rows: rows, selected: [], columns: [("RV1909", "es")]) == nil)
    }

    @Test func bookmarkToggleOverSet() {
        #expect(SelectionAnnotating.bookmarkChanges(verses: [1, 2, 3], bookmarked: [2]) == (add: [1, 3], remove: []))
        #expect(SelectionAnnotating.bookmarkChanges(verses: [1, 2], bookmarked: [1, 2, 9]) == (add: [], remove: [1, 2]))
    }
}

@MainActor @Suite struct VerseActionStateTests {
    func makeState() throws -> (AppState, UserDefaults, String) {
        let suite = "va-\(UUID().uuidString)"
        let d = try #require(UserDefaults(suiteName: suite))
        let user = try UserStore(path: NSTemporaryDirectory() + "va-\(UUID().uuidString).sqlite")
        let st = AppState(settings: AppSettings(defaults: d), defaults: d)
        st.user = user
        try st.bootstrap(db: try openDB())
        return (st, d, suite)
    }

    @Test(.enabled(if: hasDB)) func multiVerseHighlightAndBookmark() throws {
        let (st, d, suite) = try makeState(); defer { d.removePersistentDomain(forName: suite) }
        st.setTranslation("RV1909")
        st.jump(book: 43, chapter: 3, verse: 16)
        st.clickVerse(16, shift: false, command: false)
        st.clickVerse(18, shift: true, command: false)
        #expect(st.selectedVerses == [16, 17, 18])
        #expect(st.actionBarVisible)
        st.highlightSelection(.green)
        #expect(st.chapterAnnotations.highlights == [16: .green, 17: .green, 18: .green])
        #expect(st.highlightColor(of: st.targetVerses()) == .green)
        st.toggleBookmarkSelection()
        #expect(st.chapterAnnotations.bookmarks == [16, 17, 18])
        st.toggleBookmarkSelection()
        #expect(st.chapterAnnotations.bookmarks.isEmpty)
        st.removeHighlightSelection()
        #expect(st.chapterAnnotations.highlights.isEmpty)
        // «último color» tras haber usado uno
        st.highlightSelection(.pink)
        st.removeHighlightSelection()
        st.highlightWithLastColor()
        #expect(st.chapterAnnotations.highlights[17] == .pink)
        // anotar / referencias usan el rango primero...último
        st.beginNoteForSelection()
        #expect(st.noteTarget == 16...18 && st.inspectorTab == .note && st.showInspector)
        st.showCrossRefsForSelection()
        #expect(st.refsTarget == 16...18 && st.inspectorTab == .refs)
        // la selección vacía oculta la barra
        st.clearSelection()
        #expect(!st.actionBarVisible)
    }

    @Test(.enabled(if: hasDB)) func copyPlainAndReferenceForSelection() throws {
        let (st, d, suite) = try makeState(); defer { d.removePersistentDomain(forName: suite) }
        st.setTranslation("RV1909")
        st.jump(book: 43, chapter: 3, verse: 16)
        st.clickVerse(16, shift: false, command: false)
        st.clickVerse(17, shift: true, command: false)
        st.perform(.copy)
        let plain = try #require(NSPasteboard.general.string(forType: .string))
        let t16 = try #require(st.items.first { $0.number == 16 }).text.trimmingCharacters(in: .whitespaces)
        let t17 = try #require(st.items.first { $0.number == 17 }).text.trimmingCharacters(in: .whitespaces)
        #expect(plain == t16 + " " + t17)
        st.perform(.copyReference)
        #expect(NSPasteboard.general.string(forType: .string)?.hasSuffix("— Juan 3:16–17 (RV1909)") == true)
    }

    @Test(.enabled(if: hasDB)) func highlightShowsInEveryTranslation() throws {
        let (st, d, suite) = try makeState(); defer { d.removePersistentDomain(forName: suite) }
        st.setTranslation("CUV")
        st.jump(book: 43, chapter: 3, verse: 16)
        st.clickVerse(16, shift: false, command: false)
        st.highlightSelection(.yellow)
        st.toggleBookmarkSelection()
        for tr in ["RV1909", "KJV", "CUV"] {
            st.setTranslation(tr)
            #expect(st.chapterAnnotations.highlights[16] == .yellow, "\(tr)")
            #expect(st.chapterAnnotations.bookmarks == [16])
            let v = try #require(st.items.first { $0.number == 16 })
            let attr = VerseText.attributed(verses: [v], theme: Theme(palette: .light, fontScale: 1, isSepia: false),
                                            latin: tr != "CUV", selected: [], hl: st.highlight(for: tr))
            let want = ThemePalette.light.highlight[.yellow]
            #expect(attr.runs.contains { $0.backgroundColor == want }, "\(tr)")
            #expect(String(attr.characters).contains("\u{2691}"), "marcador en \(tr)")
        }
        // paralela: la misma anotación se pinta en cada columna
        st.setTranslation("RV1909")
        st.setParallel(true)
        let cols = st.parallelColumns
        #expect(cols.count >= 2)
        let row = try #require(st.parallelRows.first { $0.number == 16 })
        for (i, c) in cols.enumerated() {
            guard case .verse(let v) = row.cells[i] else { Issue.record("sin versículo en \(c.id)"); continue }
            let attr = VerseText.attributed(verses: [v], theme: Theme(palette: .dark, fontScale: 1, isSepia: false),
                                            latin: c.language != "zh", selected: [], links: false, hl: st.highlight(for: c.id))
            #expect(attr.runs.contains { $0.backgroundColor == ThemePalette.dark.highlight[.yellow] }, "\(c.id)")
        }
    }

    @Test(.enabled(if: hasDB)) func mergedVerseShowsAnyOfItsHighlights() throws {
        let (st, d, suite) = try makeState(); defer { d.removePersistentDomain(forName: suite) }
        st.setTranslation("CUV")
        st.jump(book: 4, chapter: 1, verse: 20)
        let merged = try #require(st.items.first { $0.number == 20 && $0.endNumber == 21 })
        // resaltar solo el versículo 21 (de RV1909 se vería así) → el 20–21 de CUV lo muestra
        try st.annotations?.setHighlight(.orange, book: 4, chapter: 1, verses: [21])
        st.reloadAnnotations()
        let attr = VerseText.attributed(verses: [merged], theme: Theme(palette: .sepia, fontScale: 1, isSepia: true),
                                        latin: false, selected: [], hl: st.highlight(for: "CUV"))
        #expect(attr.runs.contains { $0.backgroundColor == ThemePalette.sepia.highlight[.orange] })
        // seleccionar el 20–21 y resaltar aplica a los dos versículos reales
        st.clickVerse(20, shift: false, command: false)
        #expect(st.targetVerses() == [20, 21])
        st.highlightSelection(.blue)
        #expect(st.chapterAnnotations.highlights == [20: .blue, 21: .blue])
        // selección + resaltado: gana la selección mezclada con el color
        let sel = VerseText.attributed(verses: [merged], theme: Theme(palette: .sepia, fontScale: 1, isSepia: true),
                                       latin: false, selected: [20], hl: st.highlight(for: "CUV"))
        #expect(sel.runs.contains { $0.backgroundColor == ThemePalette.sepia.highlightSelected[.blue] })
    }

    @Test(.enabled(if: hasDB)) func strongAndCompareFromBar() throws {
        let (st, d, suite) = try makeState(); defer { d.removePersistentDomain(forName: suite) }
        st.setTranslation("CUV")
        st.jump(book: 43, chapter: 3, verse: 16)
        st.clickVerse(16, shift: false, command: false)
        #expect(!VerseActions.visible(st.actionContext).contains(.strong))
        st.setTranslation("KJV")
        st.clickVerse(16, shift: false, command: false)
        #expect(VerseActions.isEnabled(.strong, st.actionContext))
        st.perform(.strong)
        #expect(st.strongMode && st.showInspector && st.inspectorTab == .strong)
        #expect(st.strongSelection?.verse == 16)
        // comparar activa la paralela en ese versículo
        st.setStrongMode(false)
        #expect(st.selectedVerses == [16])
        st.perform(.compare)
        #expect(st.parallelOn)
        #expect(st.anchorVerse == 16)
        st.setParallel(false)
    }

    @Test(.enabled(if: hasDB)) func contextMenuScopeOutsideSelection() throws {
        let (st, d, suite) = try makeState(); defer { d.removePersistentDomain(forName: suite) }
        st.jump(book: 43, chapter: 3, verse: 16)
        st.clickVerse(16, shift: false, command: false)
        #expect(st.scope(forContextVerse: 16) == nil)      // dentro de la selección → selección
        #expect(st.scope(forContextVerse: 20) == [20])     // fuera → solo ese versículo
        st.highlightSelection(.pink, scope: [20])
        #expect(st.chapterAnnotations.highlights == [20: .pink])
        #expect(st.actionContext(scope: [20]).selectedCount == 1)
    }

    @Test(.enabled(if: hasDB)) func plainClickTogglesAndAccumulates() throws {
        let (st, d, suite) = try makeState(); defer { d.removePersistentDomain(forName: suite) }
        st.setTranslation("RV1909")
        st.jump(book: 43, chapter: 3, verse: 16)
        st.clickVerse(16, shift: false, command: false)
        #expect(st.selectedVerses == [16] && st.actionBarVisible)
        st.clickVerse(18, shift: false, command: false)
        #expect(st.selectedVerses == [16, 18])               // clic simple añade
        st.clickVerse(20, shift: false, command: false)
        #expect(st.selectedVerses == [16, 18, 20] && st.actionBarVerse == 20)
        st.clickVerse(18, shift: false, command: false)
        #expect(st.selectedVerses == [16, 20] && st.actionBarVisible)   // clic en marcado lo quita
        st.highlightSelection(.green)
        #expect(st.chapterAnnotations.highlights == [16: .green, 20: .green])
        st.clickVerse(16, shift: false, command: false)
        st.clickVerse(20, shift: false, command: false)
        #expect(st.selectedVerses.isEmpty && !st.actionBarVisible)     // vacía → barra oculta
        // ⇧-clic sigue añadiendo el rango; «Deseleccionar todo» vacía
        st.clickVerse(16, shift: false, command: false)
        st.clickVerse(18, shift: true, command: false)
        #expect(st.selectedVerses == [16, 17, 18])
        st.clearSelection()
        #expect(st.selectedVerses.isEmpty && !st.actionBarVisible)
    }
}

@Suite struct HighlightTokenTests {
    @Test func everyThemeDefinesAllColors() {
        for p in [ThemePalette.light, .dark, .sepia] {
            #expect(p.highlight.count == HighlightColor.allCases.count)
            #expect(p.highlightSelected.count == HighlightColor.allCases.count)
        }
    }

    /// BUG-V11-02: la disposición depende del ancho del panel de lectura.
    @Test func actionBarLayoutFollowsWidth() {
        #expect(ActionBarLayout.choose(width: 900, actionCount: 7) == .oneRow)
        #expect(ActionBarLayout.choose(width: 560, actionCount: 7) == .twoRows)
        #expect(ActionBarLayout.choose(width: 420, actionCount: 7) == .compact)
        #expect(ActionBarLayout.choose(width: 320, actionCount: 8) == .compact)
        // menos acciones (sin Strong ni Comparar) caben antes
        #expect(ActionBarLayout.choose(width: 560, actionCount: 6) == .twoRows)
        // compacta: acciones + 24 de margen caben en el panel mínimo (800 - barra 220 - inspector 260 = 320)
        #expect(ActionBarLayout.actionsWidth(count: 8, compact: true) + ActionBarLayout.padding <= 320)
        #expect(ActionBarLayout.swatchesWidth + ActionBarLayout.padding <= 320)
        // monótona: más ancho nunca da una disposición más apretada
        var last = 2
        for w in stride(from: 300.0, through: 1200.0, by: 10.0) {
            let l = ActionBarLayout.choose(width: w, actionCount: 8)
            let rank = l == .compact ? 0 : l == .twoRows ? 1 : 2
            #expect(rank >= last || last == 2)
            last = rank
        }
    }
}
