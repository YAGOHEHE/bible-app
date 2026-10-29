import Foundation
import BibliaCore

/// Preferencias de la vista paralela (persistidas): activada, disposición, versiones y glosas.
public struct ParallelPrefs: Equatable {
    public var on = false
    public var layout: ParallelLayout = .columns
    public var versions = VersionSet(order: [], enabled: [])
    public var glosses = GlossSet()
    public var glossesOn = true

    public init() {}

    public static func load(from d: UserDefaults, installed: [String], primary: String) -> ParallelPrefs {
        var p = ParallelPrefs()
        p.on = d.bool(forKey: "par.on")
        p.layout = ParallelLayout(rawValue: d.string(forKey: "par.layout") ?? "") ?? .columns
        p.versions = VersionSet.load(from: d, installed: installed, primary: primary)
        p.glosses = GlossSet.load(from: d)
        p.glossesOn = GlossSet.loadVisible(from: d)
        return p
    }

    public func save(to d: UserDefaults) {
        d.set(on, forKey: "par.on")
        d.set(layout.rawValue, forKey: "par.layout")
        versions.save(to: d)
        glosses.save(to: d)
        GlossSet.saveVisible(glossesOn, to: d)
    }
}

/// Cómo se pinta la lectura según el estado paralelo y el ancho disponible.
public enum ReaderMode: Equatable { case single, columns, glosses }

public enum ParallelDecision {
    /// Ancho mínimo por columna (incluye su margen); por debajo se cae al estilo glosas.
    public static let minColumnWidth: CGFloat = 300
    public static let sideMargin: CGFloat = 24

    public static func mode(on: Bool, layout: ParallelLayout, columnCount: Int, width: CGFloat) -> ReaderMode {
        guard on else { return .single }
        guard layout == .columns, columnCount >= 2 else { return .glosses }
        let colW = (width - sideMargin * 2) / CGFloat(columnCount)
        return colW >= minColumnWidth ? .columns : .glosses
    }
}

/// Lógica del gestor de versiones (S04): orden, activadas (máx. 3 columnas), principal, glosas.
public enum VersionManagerLogic {
    /// ¿Se puede cambiar la casilla de columnas de `id`? La principal siempre va; mínimo 2 y máximo 3 activadas.
    public static func canToggleColumn(_ s: VersionSet, id: String, primary: String) -> Bool {
        if id == primary { return false }
        if s.enabled.contains(id) { return s.enabledCount(primary: primary) > 2 }
        return s.enabledCount(primary: primary) < VersionSet.maxColumns
    }

    @discardableResult
    public static func toggleColumn(_ s: inout VersionSet, id: String, primary: String) -> Bool {
        guard canToggleColumn(s, id: id, primary: primary) else { return false }
        if s.enabled.contains(id) { s.enabled.remove(id) } else { s.enabled.insert(id) }
        return true
    }

    @discardableResult
    public static func move(_ s: inout VersionSet, id: String, by delta: Int) -> Bool {
        guard let i = s.order.firstIndex(of: id) else { return false }
        let j = i + delta
        guard s.order.indices.contains(j) else { return false }
        s.order.swapAt(i, j)
        return true
    }
}
