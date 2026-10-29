import Foundation

/// Acciones sobre los versículos seleccionados (barra flotante, menú contextual y barra de menús).
public enum VerseAction: String, CaseIterable, Identifiable {
    case copy, copyReference, highlight, note, bookmark, crossRefs, compare, strong
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .copy: "Copiar"
        case .copyReference: "Copiar con referencia"
        case .highlight: "Resaltar"
        case .note: "Anotar"
        case .bookmark: "Marcador"
        case .crossRefs: "Referencias"
        case .compare: "Comparar"
        case .strong: "Strong"
        }
    }

    public var symbol: String {
        switch self {
        case .copy: "doc.on.doc"
        case .copyReference: "text.quote"
        case .highlight: "highlighter"
        case .note: "square.and.pencil"
        case .bookmark: "bookmark"
        case .crossRefs: "arrow.triangle.branch"
        case .compare: "rectangle.split.2x1"
        case .strong: "textformat.abc.dottedunderline"
        }
    }
}

/// Lo que determina qué acciones hay y cuáles están activas.
public struct VerseActionContext: Equatable {
    public var selectedCount = 0
    /// Hay una versión con Strong a la vista (KJV principal o columna paralela).
    public var strongAvailable = false
    public var parallelOn = false
    /// Hay base de anotaciones (si no, resaltar/anotar/marcar no funcionan).
    public var annotationsAvailable = true
    public var hasSelection: Bool { selectedCount > 0 }
    public init(selectedCount: Int = 0, strongAvailable: Bool = false, parallelOn: Bool = false, annotationsAvailable: Bool = true) {
        self.selectedCount = selectedCount; self.strongAvailable = strongAvailable; self.parallelOn = parallelOn; self.annotationsAvailable = annotationsAvailable
    }
}

public enum VerseActions {
    /// Acciones que se muestran: Strong solo si la versión lo tiene; Comparar solo fuera de la paralela.
    public static func visible(_ c: VerseActionContext) -> [VerseAction] {
        VerseAction.allCases.filter { a in
            switch a {
            case .strong: c.strongAvailable
            case .compare: !c.parallelOn
            default: true
            }
        }
    }

    /// Activa = visible y aplicable (hay selección; las anotaciones necesitan la base de usuario).
    public static func isEnabled(_ a: VerseAction, _ c: VerseActionContext) -> Bool {
        guard c.hasSelection, visible(c).contains(a) else { return false }
        switch a {
        case .highlight, .note, .bookmark: return c.annotationsAvailable
        default: return true
        }
    }

    /// Versículos que cubre una selección. En lectura simple un versículo fusionado («20–21») aporta todos
    /// los suyos; en la paralela cada fila es un versículo exacto.
    public static func verses(selected: Set<Int>, items: [DisplayVerse], parallel: Bool) -> [Int] {
        if parallel { return selected.sorted() }
        var out = Set<Int>()
        for v in items where selected.contains(v.number) { out.formUnion(v.number...max(v.number, v.endNumber)) }
        // Seleccionados sin elemento (no debería ocurrir): se conservan tal cual.
        let covered = Set(items.map(\.number))
        out.formUnion(selected.filter { !covered.contains($0) })
        return out.sorted()
    }

    /// Rango primero...último para notas y referencias.
    public static func range(of verses: [Int]) -> ClosedRange<Int>? {
        guard let a = verses.min(), let b = verses.max() else { return nil }
        return a...b
    }
}

/// Texto plano para «Copiar» (sin referencia).
public enum PlainCopy {
    public static func text(verses: [DisplayVerse], language: String) -> String {
        let vs = verses.sorted { $0.number < $1.number }
        let joiner = language == "zh" ? "" : " "
        return vs.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }.joined(separator: joiner)
    }

    /// Paralela: una línea por versión con los versículos elegidos.
    public static func text(rows: [ParallelRow], selected: Set<Int>, columns: [(id: String, language: String)]) -> String? {
        let chosen = rows.filter { selected.contains($0.number) }
        guard !chosen.isEmpty else { return nil }
        var lines: [String] = []
        for (i, col) in columns.enumerated() {
            var seen = Set<Int>()
            var vs: [DisplayVerse] = []
            for r in chosen {
                guard let cell = r.cells[safe: i] else { continue }
                switch cell {
                case .verse(let v), .covered(let v): if seen.insert(v.number).inserted { vs.append(v) }
                case .missing: break
                }
            }
            if !vs.isEmpty { lines.append(text(verses: vs, language: col.language)) }
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }
}

/// Lógica de resaltado/marcador sobre varios versículos.
public enum SelectionAnnotating {
    /// El marcador se alterna para todo el conjunto: si todos lo tienen, se quita; si no, se pone a los que faltan.
    public static func bookmarkChanges(verses: [Int], bookmarked: Set<Int>) -> (add: [Int], remove: [Int]) {
        let all = verses.allSatisfy(bookmarked.contains)
        return all ? ([], verses) : (verses.filter { !bookmarked.contains($0) }, [])
    }
}

/// Enlaces internos del texto: icono de nota (note://ID).
public enum NoteLink {
    public static let scheme = "note"
    public static func parse(_ url: URL) -> Int64? {
        guard url.scheme == scheme, let h = url.host else { return nil }
        return Int64(h)
    }
}

/// Disposición de la barra de acciones anclada abajo del panel de lectura (BUG-V11-02).
/// Decide según el ancho realmente disponible (tras barra lateral e inspector).
public enum ActionBarLayout: Equatable {
    /// Acciones con etiqueta y muestras de color en una sola fila.
    case oneRow
    /// Acciones con etiqueta arriba, colores debajo.
    case twoRows
    /// Solo iconos (acciones) y colores debajo: cabe en ~320 pt.
    case compact

    public static let buttonWidth: CGFloat = 58
    public static let compactButtonWidth: CGFloat = 34
    public static let buttonSpacing: CGFloat = 2
    /// Icono de resaltador + 5 muestras + «Quitar» + cerrar.
    public static let swatchesWidth: CGFloat = 270
    public static let rowGap: CGFloat = 16
    public static let padding: CGFloat = 24

    public static func actionsWidth(count: Int, compact: Bool) -> CGFloat {
        let n = CGFloat(max(0, count))
        return n * (compact ? compactButtonWidth : buttonWidth) + max(0, n - 1) * buttonSpacing
    }

    public static func choose(width: CGFloat, actionCount: Int) -> ActionBarLayout {
        let full = actionsWidth(count: actionCount, compact: false)
        if full + rowGap + swatchesWidth + padding <= width { return .oneRow }
        if max(full, swatchesWidth) + padding <= width { return .twoRows }
        return .compact
    }
}
