import Testing
import Foundation
import CoreGraphics
@testable import BibliaApp
@testable import BibliaCore

private func item(_ kind: AnnotationKind, _ b: Int, _ c: Int, _ v: Int) -> AnnotationItem {
    AnnotationItem(kind: kind, book: b, chapter: c, verseStart: v, verseEnd: v, updatedAt: 0)
}

@Suite struct CodiceSidebarTests {
    @Test func groupsConsecutiveItemsByChapter() {
        let items = [item(.note, 43, 3, 16), item(.highlight, 43, 3, 18), item(.bookmark, 43, 4, 1),
                     item(.note, 45, 8, 28), item(.note, 43, 3, 1)]
        let g = AnnotationGrouping.byChapter(items)
        #expect(g.map(\.id) == ["43-3", "43-4", "45-8", "43-3"])   // el último respeta el orden (p. ej. «Recientes»)
        #expect(g[0].items.count == 2)
        #expect(AnnotationGrouping.byChapter([]).isEmpty)
    }

    @Test func recentChipsAreDistinctValidAndLimited() {
        #expect(RecentChips.books([43, 19, 43, 0, 99, 1, 2, 3, 4, 5], limit: 4) == [43, 19, 1, 2])
        #expect(RecentChips.books([]).isEmpty)
    }

    @Test func testamentSectionsCountBooks() {
        let names = (1...66).map { BookName(book: $0, language: "es", name: "L\($0)", abbrev: nil) }
        let s = TestamentSplit.sections(names)
        #expect(s.map(\.count) == [39, 27])
        #expect(s.map(\.title) == ["Antiguo Testamento", "Nuevo Testamento"])
        #expect(TestamentSplit.sections(names.filter { $0.book > 40 }).map(\.title) == ["Nuevo Testamento"])
        #expect(TestamentSplit.sections([]).isEmpty)
    }

    @Test func actionBarMetrics() {
        #expect(VerseBarMetrics.rowWidth(count: 7, compact: false) == CGFloat(460))
        #expect(VerseBarMetrics.layout(width: 900, actionCount: 7) == .oneRow)
        #expect(VerseBarMetrics.layout(width: 340, actionCount: 7) == .compact)
        // la fila compacta cabe en 320 pt
        #expect(VerseBarMetrics.rowWidth(count: 7, compact: true) + 2 * (VerseBarMetrics.innerPadding + VerseBarMetrics.outerMargin) <= CGFloat(320))
        #expect(VerseBarMetrics.swatch == 24)
        #expect(VerseBarMetrics.corner == 14)
    }
}
