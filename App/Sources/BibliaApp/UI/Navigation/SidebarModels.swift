import BibliaCore
import SwiftUI

/// Lógica pura de la barra lateral «Códice» (probada en `CodiceSidebarTests`).

/// Grupo de anotaciones del mismo capítulo (cabecera en mayúsculas pequeñas).
struct AnnotationChapterGroup: Identifiable, Equatable {
    let book: Int
    let chapter: Int
    let items: [AnnotationItem]
    var id: String { "\(book)-\(chapter)" }
}

enum AnnotationGrouping {
    /// Agrupa elementos CONSECUTIVOS del mismo capítulo (conserva el orden de la lista: bíblico o por recientes).
    static func byChapter(_ items: [AnnotationItem]) -> [AnnotationChapterGroup] {
        var out: [AnnotationChapterGroup] = []
        var cur: (book: Int, chapter: Int, items: [AnnotationItem])?
        for it in items {
            if let c = cur, c.book == it.book, c.chapter == it.chapter {
                cur?.items.append(it)
            } else {
                if let c = cur { out.append(.init(book: c.book, chapter: c.chapter, items: c.items)) }
                cur = (it.book, it.chapter, [it])
            }
        }
        if let c = cur { out.append(.init(book: c.book, chapter: c.chapter, items: c.items)) }
        return out
    }
}

/// Cápsulas de «Recientes»: libros distintos, sin vacíos, como máximo `limit`.
enum RecentChips {
    static func books(_ recents: [Int], limit: Int = 6) -> [Int] {
        var seen = Set<Int>()
        return Array(recents.filter { (1...66).contains($0) && seen.insert($0).inserted }.prefix(limit))
    }
}

/// Secciones plegables Antiguo / Nuevo Testamento con su número de libros.
struct TestamentSection: Equatable {
    let title: String
    let books: [BookName]
    var count: Int { books.count }
}

enum TestamentSplit {
    static func sections(_ names: [BookName]) -> [TestamentSection] {
        let ot = names.filter { $0.book <= 39 }, nt = names.filter { $0.book >= 40 }
        var out: [TestamentSection] = []
        if !ot.isEmpty { out.append(.init(title: "Antiguo Testamento", books: ot)) }
        if !nt.isEmpty { out.append(.init(title: "Nuevo Testamento", books: nt)) }
        return out
    }
}

/// Distribución en filas que se parte cuando no cabe (cápsulas del panel «Notas»).
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, maxX: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x > 0, x + sz.width > w { x = 0; y += rowH + lineSpacing; rowH = 0 }
            x += sz.width + spacing; rowH = max(rowH, sz.height); maxX = max(maxX, x - spacing)
        }
        return CGSize(width: maxX, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x > bounds.minX, x + sz.width > bounds.maxX { x = bounds.minX; y += rowH + lineSpacing; rowH = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(sz))
            x += sz.width + spacing; rowH = max(rowH, sz.height)
        }
    }
}
