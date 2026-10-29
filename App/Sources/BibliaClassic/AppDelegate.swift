import AppKit
import BibliaCore
import ClassicKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation, NSMenuDelegate {
    static let bundleDomain = "org.biblia.clasica"
    var settings: ClassicSettings!
    var model: ReaderModel!
    var annotations: AnnotationsModel!
    var main: MainWindowController?
    var prefs: PreferencesWindowController?
    var versions: VersionsWindowController?
    var history: HistoryWindowController?
    private var themeItems: [ThemeChoice: NSMenuItem] = [:]
    private var layoutItems: [VerseLayout: NSMenuItem] = [:]
    private var headingsItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        settings = ClassicSettings()
        let user = (try? UserStore.defaultURL(folder: "Biblia Clásica")).flatMap { try? UserStore(path: $0.path) }
        model = ReaderModel(settings: settings, user: user)
        annotations = AnnotationsModel(reader: model, store: user.map { AnnotationStore(user: $0) })
        buildMenu()
        do {
            try model.bootstrap(db: try BibleDatabase.openBundled())
        } catch {
            let a = NSAlert()
            a.messageText = "No se pudo abrir la base de datos de la Biblia"
            a.informativeText = "\(error)"
            a.runModal()
            NSApp.terminate(nil)
            return
        }
        let wc = MainWindowController(model: model, settings: settings, annotations: annotations)
        main = wc
        wc.onOpenVersions = { [weak self] in self?.showVersions(nil) }
        wc.reader.onOpenVersions = { [weak self] in self?.showVersions(nil) }
        wc.onOpenHistory = { [weak self] in self?.showHistory(nil) }
        wc.showWindow(nil)
        wc.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        model.announceInitial()
        wc.reader.focusReader()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) {
        main?.noteEditor.flush()      // la nota que se está escribiendo se guarda al salir
        model?.persist()
    }

    // MARK: actions

    @objc func showPreferences(_ sender: Any?) {
        if prefs == nil { prefs = PreferencesWindowController(settings: settings, model: model) }
        prefs?.show()
    }
    @objc func showVersions(_ sender: Any?) {
        if versions == nil { versions = VersionsWindowController(model: model) }
        versions?.show()
    }
    @objc func showHistory(_ sender: Any?) {
        if history == nil {
            let h = HistoryWindowController(model: model, settings: settings)
            h.onNavigate = { [weak self] ref, t in
                guard let self = self else { return }
                var translation: String? = t
                if self.model.parallel.on, self.model.columnIds.contains(t) { translation = nil }
                _ = self.model.navigate(to: ref, translation: translation, record: false)   // no añade otra fila
                self.main?.window?.makeKeyAndOrderFront(nil)
                self.main?.reader.focusReader()
            }
            history = h
        }
        history?.show()
    }
    @objc func findInBible(_ sender: Any?) { main?.window?.makeKeyAndOrderFront(nil); main?.showSearch() }
    @objc func findNext(_ sender: Any?) { if main?.searchNext(1) != true { NSSound.beep() } }
    @objc func findPrevious(_ sender: Any?) { if main?.searchNext(-1) != true { NSSound.beep() } }
    @objc func toggleStrong(_ sender: Any?) { main?.toggleStrong(sender) }
    @objc func toggleInspector(_ sender: Any?) { main?.toggleInspector(sender) }
    @objc func showReferences(_ sender: Any?) { main?.showReferences() }
    @objc func toggleParallel(_ sender: Any?) { model.toggleParallel() }
    @objc func pickParallelLayout(_ sender: NSMenuItem) {
        if let l = ParallelLayout(rawValue: sender.representedObject as? String ?? "") { model.setParallelLayout(l); if !model.parallel.on { model.setParallel(on: true) } }
    }
    @objc func toggleGlosses(_ sender: Any?) { model.setGlossesOn(!model.parallel.glossesOn) }
    @objc func gotoReference(_ sender: Any?) { main?.window?.makeKeyAndOrderFront(nil); main?.focusGoto() }
    @objc func copyWithReference(_ sender: Any?) { main?.commands.perform(.copyReference, scope: nil) }

    /// ⌘C: con versículos seleccionados copia los versículos; si no (o si el foco está en un campo de texto,
    /// p. ej. el editor de notas), hace la copia normal.
    @objc func copyAction(_ sender: Any?) {
        let fr = main?.window?.firstResponder
        if !(fr is NSText) || fr is ReaderTextView, main?.commands.copyVerseSelection() == true { return }
        NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: sender)
    }
    @objc func versePerform(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let a = VerseAction(rawValue: raw) else { return }
        main?.commands.perform(a, scope: nil)
    }
    @objc func verseHighlightLast(_ sender: Any?) { main?.commands.perform(.highlight, scope: nil) }
    @objc func verseRemoveHighlight(_ sender: Any?) { main?.commands.removeHighlight(scope: nil) }
    @objc func verseDeselectAll(_ sender: Any?) { main?.commands.deselectAll() }
    @objc func versePerformCopy(_ sender: Any?) { main?.commands.perform(.copy, scope: nil) }
    @objc func prevChapter(_ sender: Any?) { model.goPrev() }
    @objc func nextChapter(_ sender: Any?) { model.goNext() }
    @objc func fontLarger(_ sender: Any?) { settings.stepFont(1) }
    @objc func fontSmaller(_ sender: Any?) { settings.stepFont(-1) }
    @objc func fontReset(_ sender: Any?) { settings.resetFont() }
    @objc func pickTheme(_ sender: NSMenuItem) { if let t = ThemeChoice(rawValue: sender.representedObject as? String ?? "") { settings.theme = t } }
    @objc func pickLayout(_ sender: NSMenuItem) { if let l = VerseLayout(rawValue: sender.representedObject as? String ?? "") { settings.layout = l } }
    @objc func toggleHeadings(_ sender: Any?) { settings.showHeadings.toggle() }
    @objc func focusFilter(_ sender: Any?) { main?.sidebar.focusFilter() }

    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu.title == "Resaltar con" { self.main?.commands.fillHighlightSubmenu(menu) }
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        guard model != nil else { return false }
        switch item.action {
        case #selector(prevChapter(_:)): return model.canGoPrev
        case #selector(nextChapter(_:)): return model.canGoNext
        case #selector(fontLarger(_:)): return settings.fontScale < FontScale.max - 0.001
        case #selector(fontSmaller(_:)): return settings.fontScale > FontScale.min + 0.001
        case #selector(pickTheme(_:)):
            item.state = (item.representedObject as? String) == settings.theme.rawValue ? .on : .off
        case #selector(pickLayout(_:)):
            item.state = (item.representedObject as? String) == settings.layout.rawValue ? .on : .off
        case #selector(toggleParallel(_:)):
            item.state = model.parallel.on ? .on : .off
        case #selector(pickParallelLayout(_:)):
            item.state = (item.representedObject as? String) == model.parallel.layout.rawValue ? .on : .off
        case #selector(toggleGlosses(_:)):
            item.state = model.parallel.glossesOn ? .on : .off
            return model.parallel.on && model.parallel.layout == .interleaved
        case #selector(toggleHeadings(_:)):
            item.state = settings.showHeadings ? .on : .off
        case #selector(toggleStrong(_:)):
            item.state = settings.strongMode ? .on : .off
            return main?.strongAvailable ?? false || settings.strongMode
        case #selector(toggleInspector(_:)):
            item.state = (main?.inspectorVisible ?? false) ? .on : .off
        case #selector(copyAction(_:)):
            return true
        case #selector(versePerform(_:)), #selector(versePerformCopy(_:)):
            guard let c = main?.commands else { return false }
            let st = c.menuState(scope: nil)
            if let raw = item.representedObject as? String, let a = VerseAction(rawValue: raw) {
                if a == .bookmark { item.title = st.bookmarkTitle }
                if a == .crossRefs { item.title = st.crossRefCount > 0 ? "Referencias cruzadas (\(st.crossRefCount))" : "Referencias cruzadas" }
                return st.isEnabled(a)
            }
            return st.isEnabled(.copy)
        case #selector(verseHighlightLast(_:)): return main?.commands.menuState(scope: nil).canHighlight ?? false
        case #selector(verseRemoveHighlight(_:)): return main?.commands.menuState(scope: nil).canRemoveHighlight ?? false
        case #selector(verseDeselectAll(_:)): return !(annotations?.selection.isEmpty ?? true) || (annotations?.barVisible ?? false)
        case #selector(copyWithReference(_:)):
            return !(annotations?.selection.isEmpty ?? true) || (main?.reader.hasTextSelection ?? false)
        case #selector(findNext(_:)), #selector(findPrevious(_:)):
            return !(main?.sidebar.searchVC.search.flatHits.isEmpty ?? true)
        default: break
        }
        return true
    }

    // MARK: menu

    private func add(_ menu: NSMenu, _ title: String, _ action: Selector?, _ key: String = "",
                     _ mods: NSEvent.ModifierFlags = .command, target: AnyObject? = nil) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.keyEquivalentModifierMask = mods
        if let t = target { i.target = t } else if action != nil, action.map({ NSStringFromSelector($0) })?.hasSuffix(":") == true,
                                                      responds(to: action!) { i.target = self }
        menu.addItem(i)
        return i
    }

    private func buildMenu() {
        let main = NSMenu()
        func top(_ title: String) -> NSMenu {
            let it = NSMenuItem(); main.addItem(it)
            let m = NSMenu(title: title); it.submenu = m
            return m
        }
        let app = top("Biblia Clásica")
        _ = add(app, "Acerca de Biblia Clásica", #selector(NSApplication.orderFrontStandardAboutPanel(_:)), target: NSApp)
        app.addItem(.separator())
        _ = add(app, "Ajustes…", #selector(showPreferences(_:)), ",")
        app.addItem(.separator())
        _ = add(app, "Ocultar Biblia Clásica", #selector(NSApplication.hide(_:)), "h", target: NSApp)
        _ = add(app, "Ocultar otros", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option], target: NSApp)
        _ = add(app, "Mostrar todo", #selector(NSApplication.unhideAllApplications(_:)), "", target: NSApp)
        app.addItem(.separator())
        _ = add(app, "Salir de Biblia Clásica", #selector(NSApplication.terminate(_:)), "q", target: NSApp)

        let file = top("Archivo")
        _ = add(file, "Cerrar ventana", #selector(NSWindow.performClose(_:)), "w", target: nil)

        let edit = top("Edición")
        _ = add(edit, "Deshacer", Selector(("undo:")), "z", target: nil)
        _ = add(edit, "Rehacer", Selector(("redo:")), "z", [.command, .shift], target: nil)
        edit.addItem(.separator())
        _ = add(edit, "Cortar", #selector(NSText.cut(_:)), "x", target: nil)
        _ = add(edit, "Copiar", #selector(copyAction(_:)), "c")
        _ = add(edit, "Pegar", #selector(NSText.paste(_:)), "v", target: nil)
        _ = add(edit, "Seleccionar todo", #selector(NSText.selectAll(_:)), "a", target: nil)
        edit.addItem(.separator())
        _ = add(edit, "Ir a referencia…", #selector(gotoReference(_:)), "l")
        edit.addItem(.separator())
        _ = add(edit, "Buscar en la Biblia…", #selector(findInBible(_:)), "f")
        _ = add(edit, "Buscar siguiente", #selector(findNext(_:)), "g")
        _ = add(edit, "Buscar anterior", #selector(findPrevious(_:)), "g", [.command, .shift])
        _ = add(edit, "Filtrar libros", #selector(focusFilter(_:)), "f", [.command, .option])

        let verse = top("Versículo")
        func verseItem(_ title: String, _ a: VerseAction, _ key: String = "", _ mods: NSEvent.ModifierFlags = .command) {
            let i = add(verse, title, #selector(versePerform(_:)), key, mods)
            i.representedObject = a.rawValue
        }
        _ = add(verse, "Copiar versículos", #selector(versePerformCopy(_:)))
        _ = add(verse, "Copiar con referencia", #selector(copyWithReference(_:)), "c", [.command, .option])
        verse.addItem(.separator())
        _ = add(verse, "Resaltar con el último color", #selector(verseHighlightLast(_:)), "h", [.command, .option])
        let hlRoot = NSMenuItem(title: "Resaltar con", action: nil, keyEquivalent: ""); verse.addItem(hlRoot)
        let hlMenu = NSMenu(title: "Resaltar con"); hlMenu.delegate = self; hlRoot.submenu = hlMenu
        _ = add(verse, "Quitar resaltado", #selector(verseRemoveHighlight(_:)))
        verse.addItem(.separator())
        verseItem("Anotar…", .note, "n", [.command, .option])
        verseItem("Marcador", .bookmark, "d")
        _ = add(verse, "Referencias cruzadas", #selector(showReferences(_:)), "r", [.command, .option])
        verseItem("Comparar versiones", .compare)
        verseItem("Abrir en Strong", .strong)
        verse.addItem(.separator())
        _ = add(verse, "Deseleccionar todo", #selector(verseDeselectAll(_:)), "a", [.command, .shift])

        let view = top("Ver")
        _ = add(view, "Capítulo anterior", #selector(prevChapter(_:)), "[")
        _ = add(view, "Capítulo siguiente", #selector(nextChapter(_:)), "]")
        view.addItem(.separator())
        _ = add(view, "Aumentar tamaño", #selector(fontLarger(_:)), "+")
        _ = add(view, "Reducir tamaño", #selector(fontSmaller(_:)), "-")
        _ = add(view, "Tamaño real", #selector(fontReset(_:)), "0")
        view.addItem(.separator())
        let themeRoot = NSMenuItem(title: "Tema", action: nil, keyEquivalent: ""); view.addItem(themeRoot)
        let tm = NSMenu(title: "Tema"); themeRoot.submenu = tm
        for t in ThemeChoice.allCases {
            let i = add(tm, t.label, #selector(pickTheme(_:))); i.representedObject = t.rawValue; themeItems[t] = i
        }
        let layRoot = NSMenuItem(title: "Diseño", action: nil, keyEquivalent: ""); view.addItem(layRoot)
        let lm = NSMenu(title: "Diseño"); layRoot.submenu = lm
        for l in VerseLayout.allCases {
            let i = add(lm, l.label, #selector(pickLayout(_:))); i.representedObject = l.rawValue; layoutItems[l] = i
        }
        view.addItem(.separator())
        // ⌘\\ no se alcanza en teclados como el español (la barra invertida lleva ⌥): ⌥⌘P funciona en cualquier distribución.
        _ = add(view, "Vista paralela", #selector(toggleParallel(_:)), "p", [.command, .option])
        _ = add(view, "Vista paralela (⌘\\)", #selector(toggleParallel(_:)), "\\")
        let parRoot = NSMenuItem(title: "Disposición paralela", action: nil, keyEquivalent: ""); view.addItem(parRoot)
        let pm = NSMenu(title: "Disposición paralela"); parRoot.submenu = pm
        for l in ParallelLayout.allCases {
            let i = add(pm, MainWindowController.layoutTitle(l), #selector(pickParallelLayout(_:))); i.representedObject = l.rawValue
        }
        _ = add(view, "Mostrar glosas", #selector(toggleGlosses(_:)), "g", [.command, .option])
        _ = add(view, "Versiones…", #selector(showVersions(_:)), "v", [.command, .option])
        view.addItem(.separator())
        _ = add(view, "Modo Strong", #selector(toggleStrong(_:)), "s", [.command, .option])
        _ = add(view, "Inspector", #selector(toggleInspector(_:)), "i")
        _ = add(view, "Historial de lectura", #selector(showHistory(_:)), "y")
        view.addItem(.separator())
        headingsItem = add(view, "Mostrar títulos de sección", #selector(toggleHeadings(_:)))
        view.addItem(.separator())
        _ = add(view, "Mostrar/ocultar barra lateral", #selector(NSSplitViewController.toggleSidebar(_:)), "s", [.command, .control], target: nil)

        let win = top("Ventana")
        _ = add(win, "Minimizar", #selector(NSWindow.performMiniaturize(_:)), "m", target: nil)
        _ = add(win, "Zoom", #selector(NSWindow.performZoom(_:)), "", target: nil)
        NSApp.windowsMenu = win
        NSApp.mainMenu = main
    }
}
