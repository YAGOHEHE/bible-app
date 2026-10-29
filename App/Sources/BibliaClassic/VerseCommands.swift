import AppKit
import BibliaCore
import ClassicKit

/// Menú con cierre en lugar de target/action (menú contextual del lector).
final class BlockMenuItem: NSMenuItem {
    private var handler: (() -> Void)?
    init(_ title: String, enabled: Bool = true, checked: Bool = false, handler: @escaping () -> Void) {
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        self.handler = handler
        target = self
        isEnabled = enabled
        state = checked ? .on : .off
    }
    required init(coder: NSCoder) { fatalError() }
    @objc private func fire() { handler?() }
}

/// Acciones sobre versículos: barra, menú contextual y menú «Versículo». Un `scope` distinto de nil es el
/// ámbito de un clic derecho sobre un versículo no seleccionado (la acción afecta solo a ese versículo).
final class VerseCommands: NSObject {
    unowned let main: MainWindowController
    init(main: MainWindowController) { self.main = main }

    private var annotations: AnnotationsModel { main.annotations }
    private var model: ReaderModel { main.model }

    func menuState(scope: Set<Int>?) -> VerseMenuState {
        annotations.menuState(scope: scope, strongAvailable: main.strongAvailable, parallelOn: model.parallel.on)
    }

    // MARK: acciones

    func perform(_ a: VerseAction, scope: Set<Int>?) {
        guard menuState(scope: scope).isEnabled(a) else { NSSound.beep(); return }
        switch a {
        case .copy: main.reader.copyVerses(scope: scope, reference: false)
        case .copyReference: main.reader.copyVerses(scope: scope, reference: true)
        case .highlight: annotations.highlightWithLastColor(scope: scope)
        case .note:
            if let r = annotations.range(scope: scope) { main.openNote(range: r) }
        case .bookmark: annotations.toggleBookmark(scope: scope)
        case .crossRefs:
            if let r = annotations.range(scope: scope) { main.showReferences(range: r) }
        case .compare: compare(scope: scope)
        case .strong: openStrong(scope: scope)
        }
    }

    func highlight(_ c: HighlightColor, scope: Set<Int>?) {
        guard menuState(scope: scope).canHighlight else { NSSound.beep(); return }
        annotations.highlight(c, scope: scope)
    }

    func removeHighlight(scope: Set<Int>?) {
        guard menuState(scope: scope).canRemoveHighlight else { return }
        annotations.removeHighlight(scope: scope)
    }

    func deselectAll() { annotations.clearSelection() }

    /// ⌘C: copia los versículos seleccionados; sin versículos (o con texto seleccionado a mano) copia el texto normal.
    /// Devuelve false si no hizo nada (el llamador reenvía `copy:` a quien tenga el foco).
    func copyVerseSelection() -> Bool {
        guard !annotations.selection.isEmpty, !main.reader.hasTextSelection else { return false }
        main.reader.copyVerses(scope: nil, reference: false)
        return true
    }

    private func compare(scope: Set<Int>?) {
        guard let v = annotations.targetVerses(scope).first else { return }
        annotations.closeBar()
        main.reader.compare(at: v)
    }

    private func openStrong(scope: Set<Int>?) {
        let vs = annotations.targetVerses(scope)
        if !main.settings.strongMode { main.settings.strongMode = true }
        for id in model.strongTargets(columns: main.reader.mode == .columns) {
            let spans = model.strongSpans(for: id)
            for v in vs {
                if let sp = spans[v]?.first {
                    annotations.closeBar()
                    main.showInspector()
                    main.inspector.showStrong(StrongSelection(strong: sp.strong, verse: v, start: sp.start),
                                              translationId: id, word: sp.word, length: sp.length)
                    return
                }
            }
        }
        annotations.closeBar()
        main.showInspector()
        main.inspector.select(.strong)
    }

    // MARK: menú contextual

    func contextMenu(forVerse verse: Int?) -> NSMenu? {
        guard let v = verse else { return nil }
        let scope = annotations.scope(forContextVerse: v)
        let st = menuState(scope: scope)
        let m = NSMenu(title: "Versículo")
        m.autoenablesItems = false
        for a in VerseActions.visible(st.context) where a != .highlight {
            let title: String
            switch a {
            case .copy: title = "Copiar"
            case .copyReference: title = "Copiar con referencia"
            case .bookmark: title = st.bookmarkTitle
            case .crossRefs: title = st.refsTitle
            case .note: title = "Anotar…"
            case .strong: title = "Abrir en Strong"
            case .compare: title = "Comparar versiones"
            default: title = a.title
            }
            m.addItem(BlockMenuItem(title, enabled: st.isEnabled(a)) { [weak self] in self?.perform(a, scope: scope) })
            if a == .copyReference { m.addItem(.separator()) }
        }
        m.addItem(.separator())
        m.addItem(highlightMenuItem(scope: scope, state: st))
        m.addItem(BlockMenuItem("Quitar resaltado", enabled: st.canRemoveHighlight) { [weak self] in self?.removeHighlight(scope: scope) })
        if scope == nil, !annotations.selection.isEmpty {
            m.addItem(.separator())
            m.addItem(BlockMenuItem("Deseleccionar todo") { [weak self] in self?.deselectAll() })
        }
        return m
    }

    private func highlightMenuItem(scope: Set<Int>?, state st: VerseMenuState) -> NSMenuItem {
        let item = NSMenuItem(title: "Resaltar con", action: nil, keyEquivalent: "")
        let sub = NSMenu(title: "Resaltar con")
        sub.autoenablesItems = false
        let current = annotations.highlightColor(scope: scope)
        for c in HighlightColor.allCases {
            sub.addItem(BlockMenuItem(c.displayName, enabled: st.canHighlight, checked: current == c) { [weak self] in
                self?.highlight(c, scope: scope)
            })
        }
        item.submenu = sub
        item.isEnabled = st.canHighlight
        return item
    }

    /// Submenú «Resaltar con» del menú Versículo (se reconstruye al abrirlo).
    func fillHighlightSubmenu(_ sub: NSMenu) {
        sub.removeAllItems()
        sub.autoenablesItems = false
        let st = menuState(scope: nil)
        let current = annotations.highlightColor()
        for c in HighlightColor.allCases {
            sub.addItem(BlockMenuItem(c.displayName, enabled: st.canHighlight, checked: current == c) { [weak self] in
                self?.highlight(c, scope: nil)
            })
        }
    }
}
