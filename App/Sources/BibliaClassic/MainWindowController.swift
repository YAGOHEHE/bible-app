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
    static let aa = NSToolbarItem.Identifier("aa")
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
    private let strongButton = ToolbarChip(frame: NSRect(x: 0, y: 0, width: 84, height: 30))
    private let inspectorButton = ToolbarChip(frame: NSRect(x: 0, y: 0, width: 40, height: 30))
    var onOpenHistory: (() -> Void)?
    private let split = NSSplitViewController()
    private let prevButton = NSButton()
    private let nextButton = NSButton()
    // «Códice»: referencia («Juan 3 ⌘L»), versión (sigla en acento), Paralelo / Strong / Aa / Inspector.
    private let refButton = ToolbarChip(frame: NSRect(x: 0, y: 0, width: 176, height: 30))
    private let versionButton = ToolbarChip(frame: NSRect(x: 0, y: 0, width: 70, height: 30))
    private let gotoField = NSTextField(frame: NSRect(x: 0, y: 0, width: 252, height: 24))
    private let parallelButton = ToolbarChip(frame: NSRect(x: 0, y: 0, width: 108, height: 30))
    private let layoutControl = NSSegmentedControl(labels: ParallelLayout.allCases.map { $0 == .columns ? "Columnas" : "Intercalado" },
                                                   trackingMode: .selectOne, target: nil, action: nil)
    private let glossesPopup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 92, height: 26), pullsDown: true)
    private let aaButton = ToolbarChip(frame: NSRect(x: 0, y: 0, width: 50, height: 30))
    private let aaVC = AaPopoverController()
    private lazy var aaPopover: NSPopover = {
        let p = NSPopover(); p.behavior = .transient; p.contentViewController = aaVC; return p
    }()
    private lazy var gotoPopover: NSPopover = {
        let p = NSPopover(); p.behavior = .transient; p.contentViewController = GotoPopoverController(field: gotoField); return p
    }()
    var onOpenVersions: (() -> Void)?

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
        w.titleVisibility = .hidden        // la referencia ya está en el botón central de la barra
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

        let tb = NSToolbar(identifier: NSToolbar.Identifier("MainToolbarCodice"))
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
            s.reader.setActiveStrong(sel)
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

    @objc private func themeChanged() {
        applyWindowAppearance()
        styleToolbar()
    }

    /// Paleta, textos y estado de los controles «chip» de la barra.
    private func styleToolbar() {
        let pal = ReaderPalette.resolve(settings.theme)
        for c in [refButton, versionButton, parallelButton, strongButton, aaButton, inspectorButton] { c.palette = pal }
        let ui = NSFont.systemFont(ofSize: 13, weight: .semibold)
        refButton.parts = [.init(text: model.chapterTitle, font: ui, color: { $0.textPrimary }),
                           .init(text: "\u{2318}L", font: NSFont.systemFont(ofSize: 11), color: { $0.textMuted })]
        let sigla = model.translationId
        versionButton.parts = [.init(text: sigla, font: NSFont.systemFont(ofSize: 13, weight: .bold), color: { $0.accent })]
        versionButton.setAccessibilityValue(sigla)
        aaButton.parts = [.init(text: "Aa", font: NSFont.systemFont(ofSize: 13, weight: .semibold), color: { $0.textPrimary })]
        strongButton.parts = [.init(text: "\u{03B1}", font: NSFont.systemFont(ofSize: 14, weight: .semibold), color: { $0.textPrimary }),
                              .init(text: "Strong", font: ui, color: { $0.textPrimary })]
        parallelButton.parts = [.init(text: "Paralelo", font: ui, color: { $0.textPrimary })]
        // Con Strong inexistente en la versión el chip queda desactivado.
        aaVC.themeControl.selectedSegment = ThemeChoice.allCases.firstIndex(of: settings.theme) ?? 0
        aaVC.percent.stringValue = "\(FontScale.percent(settings.fontScale)) %"
        aaVC.smaller.isEnabled = settings.fontScale > FontScale.min + 0.001
        aaVC.larger.isEnabled = settings.fontScale < FontScale.max - 0.001
        layoutControl.setSelected(true, forSegment: ParallelLayout.allCases.firstIndex(of: model.parallel.layout) ?? 0)
    }
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
        styleToolbar()
    }

    /// Menú de versiones del chip (sigla en acento): se abre bajo el botón.
    @objc private func versionClicked(_ sender: ToolbarChip) {
        let m = NSMenu(title: "Versión")
        for t in model.translations {
            let it = NSMenuItem(title: ReaderModel.menuTitle(t), action: #selector(versionPicked(_:)), keyEquivalent: "")
            it.target = self
            it.representedObject = t.id
            it.state = t.id == model.translationId ? .on : .off
            m.addItem(it)
        }
        m.popUp(positioning: m.items.first { $0.state == .on }, at: NSPoint(x: 0, y: sender.bounds.height - 2), in: sender)
    }
    @objc private func versionPicked(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? String { model.setTranslation(id) }
        reader.focusReader()
    }

    @objc private func refClicked(_ sender: Any?) { focusGoto() }

    @objc private func aaClicked(_ sender: ToolbarChip) {
        styleToolbar()
        if aaPopover.isShown { aaPopover.performClose(nil); return }
        aaPopover.appearance = window?.appearance
        aaPopover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
    }
    @objc private func aaThemePicked(_ sender: NSSegmentedControl) {
        if let t = ThemeChoice.allCases[safe: sender.selectedSegment] { settings.theme = t }
    }
    @objc private func aaSmaller(_ sender: Any?) { settings.stepFont(-1) }
    @objc private func aaLarger(_ sender: Any?) { settings.stepFont(1) }

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
        parallelButton.chipActive = model.parallel.on
        parallelButton.setAccessibilityValue(model.parallel.on ? "activada" : "desactivada")
        layoutControl.setSelected(true, forSegment: ParallelLayout.allCases.firstIndex(of: model.parallel.layout) ?? 0)
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
    @objc private func layoutPicked(_ sender: NSSegmentedControl) {
        model.setParallelLayout(ParallelLayout.allCases[max(0, sender.selectedSegment)])
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
        strongButton.chipActive = settings.strongMode
        strongButton.isEnabled = strongAvailable
        strongButton.setAccessibilityValue(settings.strongMode ? "activado" : "desactivado")
    }

    @objc func toggleInspector(_ sender: Any?) {
        if inspectorItem.isCollapsed { showInspector() } else { inspector.flushNote(); inspectorItem.animator().isCollapsed = true; reader.setActiveStrong(nil) }
        inspectorButton.chipActive = !inspectorItem.isCollapsed
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
        inspectorButton.chipActive = true
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

    /// ⌘L / botón de referencia: popover «Ir a» bajo el botón de la barra (o bajo el lector si la barra no lo muestra).
    func focusGoto() {
        if gotoPopover.isShown { window?.makeFirstResponder(gotoField); gotoField.selectText(nil); return }
        gotoPopover.appearance = window?.appearance
        if refButton.window != nil {
            gotoPopover.show(relativeTo: refButton.bounds, of: refButton, preferredEdge: .minY)
        } else if let v = window?.contentView {
            gotoPopover.show(relativeTo: NSRect(x: v.bounds.midX - 1, y: v.bounds.maxY - 2, width: 2, height: 2), of: v, preferredEdge: .minY)
        }
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
            gotoPopover.performClose(nil)
            reader.focusReader()
        case .failed(let f):
            reader.showMessage(model.gotoMessage(f, input: text))
        }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        if sel == #selector(NSResponder.cancelOperation(_:)) {
            gotoField.stringValue = ""
            reader.hideMessage()
            gotoPopover.performClose(nil)
            reader.focusReader()
            return true
        }
        return false
    }

    // MARK: NSToolbarDelegate

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.prev, .next, .goto, .translation, .parallel, .layout, .glosses, .strong, .aa, .inspector, .flexibleSpace, .space]
    }
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        var ids: [NSToolbarItem.Identifier] = [.prev, .next, .flexibleSpace, .goto, .translation, .flexibleSpace, .parallel]
        if model.parallel.on { ids.append(.layout) }
        if model.parallel.on && model.parallel.layout == .interleaved { ids.append(.glosses) }
        return ids + [.strong, .aa, .inspector]
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
            versionButton.target = self; versionButton.action = #selector(versionClicked(_:))
            versionButton.setAccessibilityLabel("Versión")
            versionButton.toolTip = "Versión de la Biblia"
            versionButton.chevron = true
            styleToolbar()
            versionButton.frame.size.width = versionButton.fittingWidth(minWidth: 62)
            item.label = "Versión"; fit(versionButton)
        case .parallel:
            parallelButton.target = self; parallelButton.action = #selector(parallelToggled(_:))
            parallelButton.iconProvider = { ChipIcons.parallel($0) }
            parallelButton.setAccessibilityLabel("Vista paralela")
            parallelButton.toolTip = "Vista paralela (⌘\\ o ⌥⌘P)"
            styleToolbar()
            parallelButton.frame.size.width = parallelButton.fittingWidth()
            item.label = "Paralelo"; fit(parallelButton); syncParallelChrome()
        case .layout:
            layoutControl.target = self; layoutControl.action = #selector(layoutPicked(_:))
            layoutControl.setAccessibilityLabel("Disposición de la vista paralela")
            layoutControl.sizeToFit()
            item.label = "Disposición"; fit(layoutControl); syncParallelChrome()
        case .glosses:
            item.label = "Glosas"; fit(glossesPopup); syncParallelChrome()
        case .goto:
            gotoField.placeholderString = "Ir a… Juan 3:16"
            gotoField.bezelStyle = .roundedBezel
            gotoField.isBezeled = true
            gotoField.target = self
            gotoField.action = #selector(gotoSubmitted(_:))
            gotoField.delegate = self
            gotoField.setAccessibilityLabel("Ir a referencia")
            gotoField.toolTip = "Ir a referencia: Juan 3:16, 约3:16, 約3:16, John 3:16"
            refButton.target = self; refButton.action = #selector(refClicked(_:))
            refButton.chipStyle = .field
            refButton.trailingLast = true
            refButton.setAccessibilityLabel("Ir a referencia")
            refButton.toolTip = "Ir a referencia (⌘L)"
            styleToolbar()
            item.label = "Ir a"; fit(refButton)
        case .strong:
            strongButton.target = self; strongButton.action = #selector(toggleStrong(_:))
            strongButton.setAccessibilityLabel("Modo Strong")
            strongButton.toolTip = "Modo Strong (⌥⌘S)"
            styleToolbar()
            strongButton.frame.size.width = strongButton.fittingWidth()
            item.label = "Strong"; fit(strongButton); strongChrome()
        case .aa:
            aaButton.target = self; aaButton.action = #selector(aaClicked(_:))
            aaButton.setAccessibilityLabel("Tema y tamaño de letra")
            aaButton.toolTip = "Tema y tamaño de letra"
            aaVC.themeControl.target = self; aaVC.themeControl.action = #selector(aaThemePicked(_:))
            aaVC.smaller.target = self; aaVC.smaller.action = #selector(aaSmaller(_:))
            aaVC.larger.target = self; aaVC.larger.action = #selector(aaLarger(_:))
            styleToolbar()
            aaButton.frame.size.width = aaButton.fittingWidth(minWidth: 44)
            item.label = "Tema y tamaño"; fit(aaButton)
        case .inspector:
            inspectorButton.target = self; inspectorButton.action = #selector(toggleInspector(_:))
            inspectorButton.iconProvider = { ChipIcons.inspector($0) }
            inspectorButton.setAccessibilityLabel("Inspector")
            inspectorButton.toolTip = "Inspector: Strong y referencias (⌘I)"
            inspectorButton.chipActive = !inspectorItem.isCollapsed
            styleToolbar()
            inspectorButton.frame.size.width = inspectorButton.fittingWidth(minWidth: 40)
            item.label = "Inspector"; fit(inspectorButton)
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
    static func inspector(color: NSColor? = nil) -> NSImage {
        let img = NSImage(size: NSSize(width: 18, height: 14), flipped: false) { r in
            (color ?? NSColor.black).setStroke()
            let box = NSBezierPath(roundedRect: r.insetBy(dx: 1, dy: 1), xRadius: 2, yRadius: 2)
            box.lineWidth = 1.3; box.stroke()
            let bar = NSBezierPath()
            bar.move(to: NSPoint(x: r.maxX - 6, y: r.minY + 1)); bar.line(to: NSPoint(x: r.maxX - 6, y: r.maxY - 1))
            bar.lineWidth = 1.3; bar.stroke()
            (color ?? NSColor.black).setFill()
            NSRect(x: r.maxX - 5, y: r.minY + 2, width: 3.5, height: r.height - 4).fill()
            return true
        }
        img.isTemplate = color == nil
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
