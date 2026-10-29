import Foundation
import BibliaCore

/// Selección de versículos (números de fila del lector). Regla 1.1.2 (idéntica a la app moderna):
/// un clic en un versículo sin seleccionar lo AÑADE; un clic en uno seleccionado lo QUITA;
/// ⇧-clic añade el rango desde el último clic. Esc / × / «Deseleccionar todo» (⇧⌘A) la vacían.
public struct VerseSelection: Equatable {
    public private(set) var selected: Set<Int> = []
    public private(set) var lastClicked: Int?
    public init() {}

    public var isEmpty: Bool { selected.isEmpty }
    public var count: Int { selected.count }
    public var sorted: [Int] { selected.sorted() }
    public func contains(_ n: Int) -> Bool { selected.contains(n) }
    /// Versículo que debe quedar a la vista: el último pulsado si sigue seleccionado, si no el mayor.
    public var anchor: Int? {
        if let l = lastClicked, selected.contains(l) { return l }
        return selected.max()
    }

    /// `rows` = números de fila mostrados, en orden (para el rango del ⇧-clic).
    public mutating func click(_ n: Int, shift: Bool, rows: [Int]) {
        if shift, let last = lastClicked, let a = rows.firstIndex(of: last), let b = rows.firstIndex(of: n) {
            for i in min(a, b)...max(a, b) { selected.insert(rows[i]) }
        } else if selected.contains(n) {
            selected.remove(n)
        } else {
            selected.insert(n)
        }
        lastClicked = n
    }

    public mutating func clear() { selected = []; lastClicked = nil }
}

/// Qué comandos de «Versículo» (menú, menú contextual y barra) están activos y cómo se titulan.
public struct VerseMenuState: Equatable {
    public var context: VerseActionContext
    public var bookmarked: Bool
    public var hasHighlight: Bool
    public var crossRefCount: Int
    /// Hay selección de versículos (no el ámbito de un clic derecho).
    public var hasVerseSelection: Bool

    public init(context: VerseActionContext, bookmarked: Bool = false, hasHighlight: Bool = false,
                crossRefCount: Int = 0, hasVerseSelection: Bool = false) {
        self.context = context; self.bookmarked = bookmarked; self.hasHighlight = hasHighlight
        self.crossRefCount = crossRefCount; self.hasVerseSelection = hasVerseSelection
    }

    public func isEnabled(_ a: VerseAction) -> Bool { VerseActions.isEnabled(a, context) }
    /// Resaltar con un color: igual que `highlight`.
    public var canHighlight: Bool { isEnabled(.highlight) }
    public var canRemoveHighlight: Bool { canHighlight && hasHighlight }
    public var canDeselect: Bool { hasVerseSelection }
    public var bookmarkTitle: String { bookmarked ? "Quitar marcador" : "Marcador" }
    public var barBookmarkLabel: String { bookmarked ? "Quitar" : "Marcador" }
    public var refsTitle: String { crossRefCount > 0 ? "Referencias (\(crossRefCount))" : "Referencias" }
    public var refsAccessibility: String { crossRefCount > 0 ? "Referencias, \(crossRefCount)" : "Referencias" }

    /// Etiquetas cortas de la barra de acciones.
    public func barLabel(_ a: VerseAction) -> String {
        switch a {
        case .copyReference: return "Con ref."
        case .bookmark: return barBookmarkLabel
        default: return a.title
        }
    }
    public static func swatchAccessibility(_ c: HighlightColor) -> String {
        "Resaltar en " + c.displayName.lowercased()
    }
}
