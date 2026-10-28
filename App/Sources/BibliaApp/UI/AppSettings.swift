import Foundation
import Observation

enum VerseLayout: String, CaseIterable, Identifiable {
    case perLine, paragraph
    var id: String { rawValue }
    var label: String { self == .perLine ? "Un versículo por línea" : "Párrafo corrido" }
}

enum FontScale {
    static let min = 0.8, max = 2.0, step = 0.1
    static func clamp(_ v: Double) -> Double { Swift.min(max, Swift.max(min, (v * 10).rounded() / 10)) }
}

/// Ajustes de usuario (S08), persistidos en UserDefaults. Cambios en vivo.
@Observable
@MainActor
final class AppSettings {
    @ObservationIgnored private let defaults: UserDefaults

    var defaultTranslation: String { didSet { defaults.set(defaultTranslation, forKey: "set.defaultTranslation") } }
    var fontScale: Double { didSet { defaults.set(fontScale, forKey: "set.fontScale") } }
    var themeChoice: ThemeChoice { didSet { defaults.set(themeChoice.rawValue, forKey: "set.theme") } }
    var verseLayout: VerseLayout { didSet { defaults.set(verseLayout.rawValue, forKey: "set.layout") } }
    var showHeadings: Bool { didSet { defaults.set(showHeadings, forKey: "set.headings") } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaultTranslation = defaults.string(forKey: "set.defaultTranslation") ?? "CUV"
        let fs = defaults.object(forKey: "set.fontScale") as? Double ?? 1.0
        fontScale = FontScale.clamp(fs)
        themeChoice = ThemeChoice(rawValue: defaults.string(forKey: "set.theme") ?? "") ?? .system
        verseLayout = VerseLayout(rawValue: defaults.string(forKey: "set.layout") ?? "") ?? .perLine
        showHeadings = defaults.object(forKey: "set.headings") as? Bool ?? true
    }

    func stepFont(_ direction: Int) { fontScale = FontScale.clamp(fontScale + Double(direction) * FontScale.step) }
    func resetFont() { fontScale = 1.0 }
}
