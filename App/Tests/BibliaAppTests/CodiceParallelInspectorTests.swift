import Testing
import SwiftUI
import BibliaCore
@testable import BibliaApp

@Suite struct CodiceParallelInspectorTests {
    private let pal = ThemePalette.light

    @Test func metricsFollowSpec() {
        #expect(ParallelMetrics.gutter == 44)
        #expect(ParallelMetrics.columnGap == 36)
        #expect(ParallelMetrics.glossVersionGap == 6)
        #expect(ParallelMetrics.glossVerseGap == 18)
    }

    @Test func narrowWindowFallsBackToStacked() {
        // 560 pt de ventana: incluso sin barra lateral ni inspector, 2 columnas no llegan a 300 pt.
        #expect(ParallelMetrics.isStacked(availableWidth: 560, columns: 2, layout: .columns))
    }

    @Test func primaryColumnCannotBeRemoved() {
        #expect(!ParallelColumnRules.canRemove("RV1909", primary: "RV1909"))
        #expect(ParallelColumnRules.canRemove("KJV", primary: "RV1909"))
    }

    @Test func removingColumnShrinksVersionSet() {
        var v = VersionSet(order: ["RV1909", "KJV", "CUV"], enabled: ["RV1909", "KJV", "CUV"])
        #expect(v.columns(primary: "RV1909") == ["RV1909", "KJV", "CUV"])
        v.enabled.remove("KJV")
        #expect(v.columns(primary: "RV1909") == ["RV1909", "CUV"])
    }

    @Test func rowBandIsOneColorForTheWholeRow() {
        #expect(ParallelBand.fill(selected: false, highlight: nil, flashAlpha: 0, palette: pal) == nil)
        #expect(ParallelBand.fill(selected: false, highlight: .yellow, flashAlpha: 0, palette: pal) == pal.highlight[.yellow])
        #expect(ParallelBand.fill(selected: true, highlight: nil, flashAlpha: 0, palette: pal) == pal.selection)
        #expect(ParallelBand.fill(selected: true, highlight: .green, flashAlpha: 0, palette: pal) == pal.highlightSelected[.green])
        // el resaltado gana al destello; el destello solo pinta si no hay nada más
        #expect(ParallelBand.fill(selected: false, highlight: .blue, flashAlpha: 0.5, palette: pal) == pal.highlight[.blue])
        #expect(ParallelBand.fill(selected: false, highlight: nil, flashAlpha: 0.5, palette: pal) == pal.selection.opacity(0.5))
    }

    @Test func tabModel() {
        #expect(InspectorTabModel.title(.refs, refsCount: 12) == "Referencias 12")
        #expect(InspectorTabModel.title(.refs, refsCount: 0) == "Referencias")
        #expect(InspectorTabModel.title(.strong, refsCount: 12) == "Strong")
        #expect(InspectorTabModel.badge(.note, refsCount: 5) == nil)
        #expect(InspectorTab.allCases.map(\.label) == ["Strong", "Nota", "Referencias"])
    }

    @Test func strongVerseWordCapsules() {
        let spans = [StrongSpan(start: 0, length: 3, strong: "G1063", word: "For"),
                     StrongSpan(start: 4, length: 3, strong: "G3779", word: "God"),
                     StrongSpan(start: 8, length: 5, strong: "G25", word: "loved"),
                     StrongSpan(start: 20, length: 3, strong: "G2316", word: "God"),
                     StrongSpan(start: 30, length: 3, strong: "G25", word: "love")]
        let active = StrongSelection(strong: "G25", verse: 16, start: 8)
        let caps = StrongVerseWords.capsules(spans: spans, active: active)
        // sin la palabra abierta ni otras con su mismo número; «God» con dos números distintos se conserva ambas
        #expect(caps.map(\.word) == ["For", "God", "God"])
        #expect(caps.map(\.strong) == ["G1063", "G3779", "G2316"])
        #expect(StrongVerseWords.capsules(spans: spans, active: nil).count == 5)
        #expect(StrongVerseWords.capsules(spans: [], active: active).isEmpty)
    }
}

@Suite struct CodiceNarrowWindowTests {
    @Test func sidebarAutoHidesBelow720() {
        #expect(RootLayout.sidebarVisibility(windowWidth: 560) == .detailOnly)
        #expect(RootLayout.sidebarVisibility(windowWidth: 719) == .detailOnly)
        #expect(RootLayout.sidebarVisibility(windowWidth: 720) == .all)
    }

    @Test func actionBarFitsAt560() {
        // Sin barra lateral el panel mide ~560 pt: 6 acciones con etiqueta caben; con inspector abierto (~240) pasa a iconos.
        #expect(VerseBarMetrics.layout(width: 560, actionCount: 6) == .oneRow)
        #expect(VerseBarMetrics.layout(width: 240, actionCount: 6) == .compact)
    }
}
