import AppKit
import BibliaCore
import ClassicKit

private extension NSToolbarItem.Identifier {
    static let prev = NSToolbarItem.Identifier("prev")
    static let next = NSToolbarItem.Identifier("next")
    static let translation = NSToolbarItem.Identifier("translation")
    static let goto = NSToolbarItem.Identifier("goto")
    static let parallel = NSToolbarItem.Identifier("parallel")
    static let layout = NSToolbarItem.Identifier("parLayout")
    static let glosses = NSToolbarItem.Identifier("glosses")
    static let fontSmaller = NSToolbarItem.Identifier("fontSmaller")
    static let fontLarger = NSToolbarItem.Identifier("fontLarger")
}

/// Ventana principal: NSSplitViewController (barra lateral | lector) + NSToolbar.
final class MainWindowController: NSWindowController, NSToolbarDelegate, NSTextFieldDelegate {
    let model: ReaderModel
    let settings: ClassicSettings
    let reader: ReaderViewController
    let sidebar: SidebarViewController
    private let split = NSSplitViewController()
    private let prevButton = NSButton()
    private let nextButton = NSButton()
    private let translationPopup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 230, height: 26), pullsDown: false)
    private let gotoField = NSTextField(frame: NSRect(x: 0, y: 0, width: 190, height: 24))
    private let parallelButton = NSButton()
    private let layoutPopup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 176, height: 26), pullsDown: false)
    private let glossesPopup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 92, height: 26), pullsDown: true)
    var onOpenVersions: (() -> Void)?
    private let smaller = NSButton()
    private let larger = NSButton()

    init(model: ReaderModel, settings: ClassicSettings) {
        self.model = model; self.settings = settings
        reader = ReaderViewController(model: model, settings: settings)
        sidebar = SidebarViewController(model: model, settings: settings)

        let side = NSSplitViewItem(viewController: sidebar)
        side.minimumThickness = 200
        side.maximumThickness = 320
        side.holdingPriority = NSLayoutConstraint.Priority(260)
        side.canCollapse = true
        let content = NSSplitViewItem(viewController: reader)
        content.minimumThickness = 360
        split.addSplitViewItem(side)
        split.addSplitViewItem(content)
        split.splitView.dividerStyle = .thin
        split.splitView.autosaveName = NSSplitView.AutosaveName("MainSplit")

        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable],
                         backing: .buffered, defer: false)
        w.contentViewController = split
        w.setContentSize(NSSize(width: 1000, height: 700))
        w.minSize = NSSize(width: 720, height: 480)
        w.title = "Biblia Clásica"
        w.center()
        w.setFrameAutosaveName("MainWindow")
        super.init(window: w)

        let tb = NSToolbar(identifier: NSToolbar.Identifier("MainToolbar"))
        tb.delegate = self
        tb.displayMode = .iconOnly
        tb.allowsUserCustomization = false
        w.toolbar = tb

        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(refreshChrome), name: .classicChapterChanged, object: model)
        nc.addObserver(self, selector: #selector(refreshChrome), name: .classicTranslationChanged, object: model)
        nc.addObserver(self, selector: #selector(parallelChromeChanged), name: .classicParallelChanged, object: model)
        nc.addObserver(self, selector: #selector(parallelChromeChanged), name: .classicTranslationChanged, object: model)
        nc.addObserver(self, selector: #selector(themeChanged), name: .classicSettingsChanged, object: settings)
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(systemAppearanceChanged),
                                                            name: NSNotification.Name("AppleInterfaceThemeChangedNotification"), object: nil)
        applyWindowAppearance()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) no se usa") }

    // MARK: theme

    /// 10.14+: la apariencia de la ventana (barra de título, barra de herramientas, barras de desplazamiento) sigue el tema.
    /// 10.13: no existe el modo oscuro de sistema; los colores del tema se aplican directamente a las vistas.
    func applyWindowAppearance() {
        guard let w = window else { return }
        MainWindowController.apply(theme: settings.theme, to: w)
    }

    static func apply(theme: ThemeChoice, to w: NSWindow) {
        if #available(macOS 10.14, *) {
            switch theme {
            case .system: w.appearance = nil
            case .dark: w.appearance = NSAppearance(named: .darkAqua)
            case .light, .sepia: w.appearance = NSAppearance(named: .aqua)
            }
        }
        w.backgroundColor = ReaderPalette.resolve(theme).background
    }

    @objc private func themeChanged() { applyWindowAppearance() }
    @objc private func systemAppearanceChanged() {
        guard settings.theme == .system else { return }
        // La apariencia efectiva de la app se actualiza un instante después de la notificación.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let s = self else { return }
            NotificationCenter.default.post(name: .classicSettingsChanged, object: s.settings)
        }
    }

    // MARK: chrome

    @objc private func refreshChrome() {
        window?.title = "\(model.chapterTitle) — Biblia Clásica"
        prevButton.isEnabled = model.canGoPrev
        nextButton.isEnabled = model.canGoNext
        rebuildTranslationPopup()
    }

    private func rebuildTranslationPopup() {
        translationPopup.removeAllItems()
        for t in model.translations {
            translationPopup.addItem(withTitle: ReaderModel.menuTitle(t))
            translationPopup.lastItem?.representedObject = t.id
        }
        if let i = model.translations.firstIndex(where: { $0.id == model.translationId }) { translationPopup.selectItem(at: i) }
    }

    // MARK: parallel chrome

    @objc private func parallelChromeChanged() {
        syncParallelChrome()
        syncToolbarItems()
    }

    private func syncToolbarItems() {
        guard let tb = window?.toolbar else { return }
        func index(_ id: NSToolbarItem.Identifier) -> Int? { tb.items.firstIndex { $0.itemIdentifier == id } }
        func adjust(_ id: NSToolbarItem.Identifier, want: Bool, after: NSToolbarItem.Identifier) {
            let idx = index(id)
            if want, idx == nil, let a = index(after) { tb.insertItem(withItemIdentifier: id, at: a + 1) }
            else if !want, let i = idx { tb.removeItem(at: i) }
        }
        let on = model.parallel.on
        adjust(.layout, want: on, after: .parallel)
        adjust(.glosses, want: on && model.parallel.layout == .interleaved, after: on ? .layout : .parallel)
    }

    func syncParallelChrome() {
        parallelButton.state = model.parallel.on ? .on : .off
        parallelButton.setAccessibilityValue(model.parallel.on ? "activada" : "desactivada")
        layoutPopup.selectItem(at: ParallelLayout.allCases.firstIndex(of: model.parallel.layout) ?? 0)
        rebuildGlossesMenu()
    }

    static func layoutTitle(_ l: ParallelLayout) -> String { l == .columns ? "Columnas" : "Intercalado (glosas)" }

    private func rebuildGlossesMenu() {
        let m = NSMenu(title: "Glosas")
        m.autoenablesItems = false
        m.addItem(NSMenuItem(title: "Glosas", action: nil, keyEquivalent: ""))      // título del botón desplegable
        let on = NSMenuItem(title: "Mostrar glosas", action: #selector(toggleGlossesVisible(_:)), keyEquivalent: "")
        on.target = self; on.state = model.parallel.glossesOn ? .on : .off
        m.addItem(on)
        m.addItem(.separator())
        for g in GlossSet.grouped(model.translations, primary: model.translationId) {
            let h = NSMenuItem(title: languageLabel(g.language), action: nil, keyEquivalent: "")
            h.isEnabled = false
            m.addItem(h)
            for t in g.items {
                let it = NSMenuItem(title: ReaderModel.menuTitle(t), action: #selector(glossPicked(_:)), keyEquivalent: "")
                it.target = self
                it.representedObject = t.id
                it.state = model.parallel.glosses.contains(t.id) ? .on : .off
                it.isEnabled = model.parallel.glosses.canAdd(t.id, primary: model.translationId)
                it.indentationLevel = 1
                m.addItem(it)
            }
        }
        m.addItem(.separator())
        let v = NSMenuItem(title: "Gestor de versiones…", action: #selector(openVersions(_:)), keyEquivalent: "")
        v.target = self
        m.addItem(v)
        glossesPopup.menu = m
        glossesPopup.setAccessibilityLabel("Glosas")
        glossesPopup.toolTip = "Elegir glosas (máx. 3, sin la versión principal)"
    }

    @objc private func glossPicked(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        if !model.toggleGloss(id) { NSSound.beep() }
    }
    @objc private func toggleGlossesVisible(_ sender: Any?) { model.setGlossesOn(!model.parallel.glossesOn) }
    @objc private func openVersions(_ sender: Any?) { onOpenVersions?() }
    @objc private func parallelToggled(_ sender: Any?) { model.toggleParallel(); reader.focusReader() }
    @objc private func layoutPicked(_ sender: NSPopUpButton) {
        model.setParallelLayout(ParallelLayout.allCases[max(0, sender.indexOfSelectedItem)])
    }

    // MARK: actions

    @objc func prevChapter(_ sender: Any?) { model.goPrev() }
    @objc func nextChapter(_ sender: Any?) { model.goNext() }
    @objc func fontSmaller(_ sender: Any?) { settings.stepFont(-1) }
    @objc func fontLarger(_ sender: Any?) { settings.stepFont(1) }
    @objc func fontReset(_ sender: Any?) { settings.resetFont() }

    @objc private func translationPicked(_ sender: NSPopUpButton) {
        if let id = sender.selectedItem?.representedObject as? String { model.setTranslation(id) }
        reader.focusReader()
    }

    func focusGoto() {
        window?.makeFirstResponder(gotoField)
        gotoField.selectText(nil)
    }

    @objc private func gotoSubmitted(_ sender: NSTextField) {
        let text = sender.stringValue
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        switch model.goTo(text) {
        case .went:
            reader.hideMessage()
            sender.stringValue = ""
            reader.focusReader()
        case .failed(let f):
            reader.showMessage(model.gotoMessage(f, input: text))
        }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        if sel == #selector(NSResponder.cancelOperation(_:)) {
            gotoField.stringValue = ""
            reader.hideMessage()
            reader.focusReader()
            return true
        }
        return false
    }

    // MARK: NSToolbarDelegate

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.prev, .next, .translation, .parallel, .layout, .glosses, .goto, .fontSmaller, .fontLarger, .flexibleSpace, .space]
    }
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        var ids: [NSToolbarItem.Identifier] = [.prev, .next, .translation, .parallel]
        if model.parallel.on { ids.append(.layout) }
        if model.parallel.on && model.parallel.layout == .interleaved { ids.append(.glosses) }
        return ids + [.flexibleSpace, .goto, .fontSmaller, .fontLarger]
    }

    private func configure(_ b: NSButton, image: NSImage?, title: String, action: Selector, size: NSSize) {
        b.bezelStyle = .texturedRounded
        b.target = self
        b.action = action
        b.frame = NSRect(origin: .zero, size: size)
        if let i = image { b.image = i; b.imagePosition = .imageOnly } else { b.title = title }
        b.setAccessibilityLabel(title)
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: id)
        func fit(_ v: NSView) { item.view = v; item.minSize = v.frame.size; item.maxSize = v.frame.size }
        switch id {
        case .prev:
            configure(prevButton, image: NSImage(named: NSImage.goLeftTemplateName), title: "Capítulo anterior",
                      action: #selector(prevChapter(_:)), size: NSSize(width: 36, height: 25))
            prevButton.toolTip = "Capítulo anterior (⌘[)"
            item.label = "Anterior"; fit(prevButton)
        case .next:
            configure(nextButton, image: NSImage(named: NSImage.goRightTemplateName), title: "Capítulo siguiente",
                      action: #selector(nextChapter(_:)), size: NSSize(width: 36, height: 25))
            nextButton.toolTip = "Capítulo siguiente (⌘])"
            item.label = "Siguiente"; fit(nextButton)
        case .translation:
            translationPopup.target = self
            translationPopup.action = #selector(translationPicked(_:))
            translationPopup.setAccessibilityLabel("Versión")
            translationPopup.toolTip = "Versión de la Biblia"
            rebuildTranslationPopup()
            item.label = "Versión"; fit(translationPopup)
        case .parallel:
            configure(parallelButton, image: ParallelIcon.image(), title: "Vista paralela", action: #selector(parallelToggled(_:)), size: NSSize(width: 36, height: 25))
            parallelButton.setButtonType(.pushOnPushOff)
            parallelButton.alternateImage = ParallelIcon.image(color: NSColor.alternateSelectedControlColor)
            parallelButton.toolTip = "Vista paralela (⌘\\)"
            item.label = "Paralela"; fit(parallelButton); syncParallelChrome()
        case .layout:
            if layoutPopup.numberOfItems == 0 {
                for l in ParallelLayout.allCases { layoutPopup.addItem(withTitle: MainWindowController.layoutTitle(l)) }
                layoutPopup.target = self; layoutPopup.action = #selector(layoutPicked(_:))
                layoutPopup.setAccessibilityLabel("Disposición de la vista paralela")
            }
            item.label = "Disposición"; fit(layoutPopup); syncParallelChrome()
        case .glosses:
            item.label = "Glosas"; fit(glossesPopup); syncParallelChrome()
        case .goto:
            gotoField.placeholderString = "Ir a… (⌘L)"
            gotoField.bezelStyle = .roundedBezel
            gotoField.isBezeled = true
            gotoField.target = self
            gotoField.action = #selector(gotoSubmitted(_:))
            gotoField.delegate = self
            gotoField.setAccessibilityLabel("Ir a referencia")
            gotoField.toolTip = "Ir a referencia: Juan 3:16, 约3:16, 約3:16, John 3:16"
            item.label = "Ir a"; fit(gotoField)
        case .fontSmaller:
            configure(smaller, image: nil, title: "Reducir tamaño de letra", action: #selector(fontSmaller(_:)), size: NSSize(width: 34, height: 25))
            smaller.attributedTitle = NSAttributedString(string: "A", attributes: [.font: NSFont.systemFont(ofSize: 11)])
            smaller.toolTip = "Reducir tamaño (⌘−)"
            item.label = "Menor"; fit(smaller)
        case .fontLarger:
            configure(larger, image: nil, title: "Aumentar tamaño de letra", action: #selector(fontLarger(_:)), size: NSSize(width: 34, height: 25))
            larger.attributedTitle = NSAttributedString(string: "A", attributes: [.font: NSFont.systemFont(ofSize: 17)])
            larger.toolTip = "Aumentar tamaño (⌘+)"
            item.label = "Mayor"; fit(larger)
        default:
            return nil
        }
        return item
    }
}

/// Icono de «vista paralela» (dos columnas), dibujado como plantilla: no usa SF Symbols (inexistentes en 10.13).
enum ParallelIcon {
    /// `color` nil = plantilla (se tiñe sola); con color = versión «activada» (acento del sistema).
    static func image(color: NSColor? = nil) -> NSImage {
        let img = NSImage(size: NSSize(width: 18, height: 14), flipped: false) { r in
            (color ?? NSColor.black).setStroke()
            let box = NSBezierPath(roundedRect: r.insetBy(dx: 1, dy: 1), xRadius: 2, yRadius: 2)
            box.lineWidth = 1.3
            box.stroke()
            let mid = NSBezierPath()
            mid.move(to: NSPoint(x: r.midX, y: r.minY + 1)); mid.line(to: NSPoint(x: r.midX, y: r.maxY - 1))
            mid.lineWidth = 1.3
            mid.stroke()
            return true
        }
        img.isTemplate = color == nil
        return img
    }
}
