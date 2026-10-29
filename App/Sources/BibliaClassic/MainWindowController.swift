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
    static let strong = NSToolbarItem.Identifier("strong")
    static let history = NSToolbarItem.Identifier("history")
    static let inspector = NSToolbarItem.Identifier("inspector")
}

/// Ventana principal: NSSplitViewController (barra lateral | lector) + NSToolbar.
final class MainWindowController: NSWindowController, NSToolbarDelegate, NSTextFieldDelegate {
    let model: ReaderModel
    let settings: ClassicSettings
    let reader: ReaderViewController
    let sidebar: SidebarViewController
    let inspector: InspectorViewController
    let annotations: AnnotationsModel
    let noteEditor = NoteEditorModel()
    private(set) var commands: VerseCommands!
    private var inspectorItem: NSSplitViewItem!
    private var sidebarItem: NSSplitViewItem!
    private let strongButton = NSButton()
    private let inspectorButton = NSButton()
    private let historyButton = NSButton()
    var onOpenHistory: (() -> Void)?
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

    init(model: ReaderModel, settings: ClassicSettings, annotations: AnnotationsModel) {
        self.model = model; self.settings = settings; self.annotations = annotations
        noteEditor.store = annotations.store
        reader = ReaderViewController(model: model, settings: settings, annotations: annotations)
        sidebar = SidebarViewController(model: model, settings: settings, annotations: annotations)
        inspector = InspectorViewController(model: model, settings: settings, annotations: annotations, noteEditor: noteEditor)

        let side = NSSplitViewItem(viewController: sidebar)
        side.minimumThickness = 200
        side.maximumThickness = 520
        side.holdingPriority = NSLayoutConstraint.Priority(260)
        side.canCollapse = true
        let content = NSSplitViewItem(viewController: reader)
        content.minimumThickness = 360
        let insp = NSSplitViewItem(viewController: inspector)
        insp.minimumThickness = 260
        insp.maximumThickness = 440
        insp.holdingPriority = NSLayoutConstraint.Priority(250)
        insp.canCollapse = true
        insp.isCollapsed = true
        sidebarItem = side
        inspectorItem = insp
        split.addSplitViewItem(side)
        split.addSplitViewItem(content)
        split.addSplitViewItem(insp)
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
        commands = VerseCommands(main: self)
        reader.commands = commands
        noteEditor.onChange = { [weak annotations] in annotations?.didMutate() }
        inspector.onRequestNote = { [weak self] in self?.commands.perform(.note, scope: nil) }
        reader.onOpenNote = { [weak self] id in self?.openNote(id: id) }
        sidebar.notesVC.onOpen = { [weak self] item in self?.openAnnotation(item) }
        NotificationCenter.default.addObserver(self, selector: #selector(selectionChangedForInspector), name: .classicSelectionChanged, object: annotations)
        NotificationCenter.default.addObserver(self, selector: #selector(windowWillClose(_:)), name: NSWindow.willCloseNotification, object: w)

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
        nc.addObserver(self, selector: #selector(strongChrome), name: .classicSettingsChanged, object: settings)
        nc.addObserver(self, selector: #selector(strongChrome), name: .classicTranslationChanged, object: model)
        nc.addObserver(self, selector: #selector(strongChrome), name: .classicParallelChanged, object: model)
        sidebar.onModeChanged = { [weak self] m in self?.sidebarModeChanged(m) }
        reader.onStrongClicked = { [weak self] sel, id, word, len in
            guard let s = self else { return }
            s.showInspector()
            s.inspector.showStrong(sel, translationId: id, word: word, length: len)
        }
        inspector.onNavigate = { [weak self] ref, t in self?.navigateFromInspector(ref, t) }
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

    // MARK: búsqueda / Strong / inspector

    private func sidebarModeChanged(_ m: SidebarViewController.Mode) {
        guard m == .search || m == .notes else { return }
        if let it = sidebarItem, it.isCollapsed { it.animator().isCollapsed = false }
        // El panel de resultados necesita más ancho que la lista de libros.
        let w = sidebar.view.frame.width
        if w < 300 { split.splitView.setPosition(340, ofDividerAt: 0) }
    }

    func showSearch() {
        if let it = sidebarItem, it.isCollapsed { it.isCollapsed = false }
        sidebar.showSearch()
    }
    func searchNext(_ d: Int) -> Bool { sidebar.searchVC.advance(d) }

    var strongAvailable: Bool { !model.strongTargets(columns: reader.mode == .columns).isEmpty }

    @objc func toggleStrong(_ sender: Any?) {
        guard strongAvailable || settings.strongMode else {
            NSSound.beep()
            reader.showMessage("El modo Strong solo existe en versiones con numeración Strong (KJV).")
            return
        }
        settings.strongMode.toggle()
    }

    @objc private func strongChrome() {
        strongButton.state = settings.strongMode ? .on : .off
        strongButton.isEnabled = strongAvailable
        strongButton.setAccessibilityValue(settings.strongMode ? "activado" : "desactivado")
        strongButton.attributedTitle = MainWindowController.strongTitle(on: settings.strongMode, enabled: strongAvailable)
    }

    static func strongTitle(on: Bool, enabled: Bool) -> NSAttributedString {
        let c = on ? NSColor.alternateSelectedControlColor : NSColor.labelColor
        return NSAttributedString(string: "abc", attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: enabled ? c : NSColor.disabledControlTextColor,
            .underlineStyle: NSNumber(value: NSUnderlineStyle.single.rawValue | NSUnderlineStyle.patternDot.rawValue),
            .underlineColor: enabled ? c : NSColor.disabledControlTextColor])
    }

    @objc func toggleInspector(_ sender: Any?) {
        if inspectorItem.isCollapsed { showInspector() } else { inspector.flushNote(); inspectorItem.animator().isCollapsed = true }
        inspectorButton.state = inspectorItem.isCollapsed ? .off : .on
    }

    func showInspector() {
        guard inspectorItem.isCollapsed, let w = window else { return }
        // Si la ventana es estrecha, ensancharla para que el lector conserve su ancho mínimo.
        let side = sidebarItem.isCollapsed ? 0 : sidebar.view.frame.width
        let need = side + 360 + 300
        let have = w.contentView?.frame.width ?? 0
        if have < need, let screen = w.screen {
            var f = w.frame
            f.size.width = min(f.width + (need - have), screen.visibleFrame.width)
            f.origin.x = min(f.origin.x, screen.visibleFrame.maxX - f.width)
            w.setFrame(f, display: true)
        }
        inspectorItem.isCollapsed = false
        inspectorButton.state = .on
    }

    var inspectorVisible: Bool { !inspectorItem.isCollapsed }

    @objc private func windowWillClose(_ n: Notification) { noteEditor.flush() }

    /// Abre la pestaña «Nota» sobre `range` del capítulo actual (con la nota `selecting` si se indica).
    func openNote(range: ClosedRange<Int>, selecting id: Int64? = nil, book: Int? = nil, chapter: Int? = nil) {
        noteEditor.load(book: book ?? model.book, chapter: chapter ?? model.chapter, range: range, selecting: id)
        noteEditor.preview = false           // abrir una nota es para escribir: vuelve a «Editar»
        showInspector()
        inspector.select(.note)
        inspector.focusNoteEditor()
    }

    /// Icono ✎ del texto: abre la nota (en el capítulo mostrado).
    func openNote(id: Int64) {
        guard let n = annotations.chapter.notes.first(where: { $0.id == id }) else { return }
        openNote(range: n.range, selecting: id)
    }

    /// Fila del panel «Notas»: navega al pasaje y, si es una nota, la abre.
    func openAnnotation(_ item: AnnotationItem) {
        let hi = max(item.verseStart, item.verseEnd)
        _ = model.navigate(to: BibleRef(book: item.book, chapter: item.chapter, verseFrom: item.verseStart, verseTo: hi))
        if item.kind == .note { openNote(range: item.verseStart...hi, selecting: item.noteId, book: item.book, chapter: item.chapter) }
    }

    /// Con el inspector abierto en «Referencias», sigue la selección (primer..último versículo).
    @objc private func selectionChangedForInspector() {
        guard inspectorVisible, inspector.tab == .refs, let r = annotations.range() else { return }
        inspector.showRefs(book: model.book, chapter: model.chapter, verses: Array(r), switchTab: false)
    }

    func showReferences(range: ClosedRange<Int>) {
        showInspector()
        inspector.showRefs(book: model.book, chapter: model.chapter, verses: Array(range))
    }

    /// «Referencias del versículo…»: versículo(s) seleccionados; si no hay, bajo la selección de texto o el cursor.
    func showReferences() {
        if let r = annotations.range() { showReferences(range: r); return }
        let vs = reader.currentVerses()
        guard !vs.isEmpty else {
            NSSound.beep()
            reader.showMessage("Coloca el cursor o selecciona texto en un versículo para ver sus referencias.")
            return
        }
        showInspector()
        inspector.showRefs(book: model.book, chapter: model.chapter, verses: vs)
    }

    private func navigateFromInspector(_ ref: BibleRef, _ t: String?) {
        // Si esa versión ya está en pantalla (columna), no se cambia la principal.
        var translation = t
        if let x = t, model.parallel.on, model.columnIds.contains(x) { translation = nil }
        if !model.navigate(to: ref, translation: translation) { NSSound.beep() }
    }

    @objc private func openHistory(_ sender: Any?) { onOpenHistory?() }

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
        [.prev, .next, .translation, .parallel, .layout, .glosses, .goto, .strong, .history, .inspector, .fontSmaller, .fontLarger, .flexibleSpace, .space]
    }
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        var ids: [NSToolbarItem.Identifier] = [.prev, .next, .translation, .parallel]
        if model.parallel.on { ids.append(.layout) }
        if model.parallel.on && model.parallel.layout == .interleaved { ids.append(.glosses) }
        return ids + [.flexibleSpace, .goto, .strong, .history, .inspector, .fontSmaller, .fontLarger]
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
            parallelButton.toolTip = "Vista paralela (⌘\\ o ⌥⌘P)"
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
        case .strong:
            configure(strongButton, image: nil, title: "Modo Strong", action: #selector(toggleStrong(_:)), size: NSSize(width: 46, height: 25))
            strongButton.setButtonType(.pushOnPushOff)
            strongButton.toolTip = "Modo Strong (⌥⌘S)"
            item.label = "Strong"; fit(strongButton); strongChrome()
        case .history:
            configure(historyButton, image: ToolbarIcons.clock(), title: "Historial de lectura", action: #selector(openHistory(_:)), size: NSSize(width: 36, height: 25))
            historyButton.toolTip = "Historial de lectura (⌘Y)"
            item.label = "Historial"; fit(historyButton)
        case .inspector:
            configure(inspectorButton, image: ToolbarIcons.inspector(), title: "Inspector", action: #selector(toggleInspector(_:)), size: NSSize(width: 36, height: 25))
            inspectorButton.setButtonType(.pushOnPushOff)
            inspectorButton.state = inspectorItem.isCollapsed ? .off : .on
            inspectorButton.toolTip = "Inspector: Strong y referencias (⌘I)"
            item.label = "Inspector"; fit(inspectorButton)
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

/// Iconos de la barra de herramientas dibujados como plantillas (sin SF Symbols, inexistentes en 10.13).
enum ToolbarIcons {
    static func inspector() -> NSImage {
        let img = NSImage(size: NSSize(width: 18, height: 14), flipped: false) { r in
            NSColor.black.setStroke()
            let box = NSBezierPath(roundedRect: r.insetBy(dx: 1, dy: 1), xRadius: 2, yRadius: 2)
            box.lineWidth = 1.3; box.stroke()
            let bar = NSBezierPath()
            bar.move(to: NSPoint(x: r.maxX - 6, y: r.minY + 1)); bar.line(to: NSPoint(x: r.maxX - 6, y: r.maxY - 1))
            bar.lineWidth = 1.3; bar.stroke()
            NSColor.black.setFill()
            NSRect(x: r.maxX - 5, y: r.minY + 2, width: 3.5, height: r.height - 4).fill()
            return true
        }
        img.isTemplate = true
        return img
    }

    static func clock() -> NSImage {
        let img = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { r in
            NSColor.black.setStroke()
            let c = NSBezierPath(ovalIn: r.insetBy(dx: 1.5, dy: 1.5)); c.lineWidth = 1.3; c.stroke()
            let h = NSBezierPath()
            h.move(to: NSPoint(x: r.midX, y: r.midY + 4)); h.line(to: NSPoint(x: r.midX, y: r.midY)); h.line(to: NSPoint(x: r.midX + 3.2, y: r.midY - 2))
            h.lineWidth = 1.3; h.lineCapStyle = .round; h.lineJoinStyle = .round; h.stroke()
            return true
        }
        img.isTemplate = true
        return img
    }
}
