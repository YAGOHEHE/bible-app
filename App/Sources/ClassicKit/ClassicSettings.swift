import Foundation

public enum ThemeChoice: String, CaseIterable {
    case system, light, dark, sepia
    public var label: String {
        switch self {
        case .system: return "Sistema"
        case .light: return "Claro"
        case .dark: return "Oscuro"
        case .sepia: return "Sepia"
        }
    }
}

public enum VerseLayout: String, CaseIterable {
    case paragraph, perLine
    public var label: String { self == .perLine ? "Un versículo por línea" : "Párrafos" }
}

public enum FontScale {
    public static let min = 0.8, max = 2.0, step = 0.1
    public static func clamp(_ v: Double) -> Double { Swift.min(max, Swift.max(min, (v * 10).rounded() / 10)) }
    public static func percent(_ v: Double) -> Int { Int((v * 100).rounded()) }
}

public extension Notification.Name {
    /// Cambió algún ajuste (tema, tamaño, diseño, títulos, versión predeterminada).
    static let classicSettingsChanged = Notification.Name("org.biblia.clasica.settingsChanged")
    /// Cambió el capítulo mostrado (userInfo: "scrollTo": Int?, "flashFrom"/"flashTo": Int?).
    static let classicChapterChanged = Notification.Name("org.biblia.clasica.chapterChanged")
    /// Cambió la versión (traducción) activa.
    static let classicTranslationChanged = Notification.Name("org.biblia.clasica.translationChanged")
    /// Cambió algo de la vista paralela (activada, disposición, versiones, glosas).
    static let classicParallelChanged = Notification.Name("org.biblia.clasica.parallelChanged")
    /// Cambió la lista de recientes.
    static let classicRecentsChanged = Notification.Name("org.biblia.clasica.recentsChanged")
}

/// Ajustes de usuario (S08), persistidos en UserDefaults; cada cambio notifica `classicSettingsChanged`.
public final class ClassicSettings {
    private let defaults: UserDefaults
    var defaultsForTests: UserDefaults { defaults }
    private let center: NotificationCenter

    public var defaultTranslation: String { didSet { save(defaultTranslation, "set.defaultTranslation") } }
    public var fontScale: Double { didSet { fontScale = FontScale.clamp(fontScale); save(fontScale, "set.fontScale") } }
    public var theme: ThemeChoice { didSet { save(theme.rawValue, "set.theme") } }
    public var layout: VerseLayout { didSet { save(layout.rawValue, "set.layout") } }
    public var showHeadings: Bool { didSet { save(showHeadings, "set.headings") } }
    /// Modo Strong (⌥⌘S): subraya con puntos las palabras etiquetadas de las versiones con Strong.
    public var strongMode: Bool { didSet { save(strongMode, "set.strongMode") } }

    public init(defaults: UserDefaults = .standard, center: NotificationCenter = .default) {
        self.defaults = defaults
        self.center = center
        defaultTranslation = defaults.string(forKey: "set.defaultTranslation") ?? "CUV"
        fontScale = FontScale.clamp(defaults.object(forKey: "set.fontScale") as? Double ?? 1.0)
        theme = ThemeChoice(rawValue: defaults.string(forKey: "set.theme") ?? "") ?? .system
        layout = VerseLayout(rawValue: defaults.string(forKey: "set.layout") ?? "") ?? .paragraph
        showHeadings = defaults.object(forKey: "set.headings") as? Bool ?? true
        strongMode = defaults.object(forKey: "set.strongMode") as? Bool ?? false
    }

    private func save(_ v: Any, _ key: String) {
        defaults.set(v, forKey: key)
        center.post(name: .classicSettingsChanged, object: self)
    }

    public func stepFont(_ direction: Int) { fontScale = fontScale + Double(direction) * FontScale.step }
    public func resetFont() { fontScale = 1.0 }
}
