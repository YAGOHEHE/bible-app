import AppKit
import BibliaCore
import ClassicKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    static let bundleDomain = "org.biblia.clasica"
    var settings: ClassicSettings!
    var model: ReaderModel!
    var main: MainWindowController?
    var prefs: PreferencesWindowController?
    private var themeItems: [ThemeChoice: NSMenuItem] = [:]
    private var layoutItems: [VerseLayout: NSMenuItem] = [:]
    private var headingsItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        settings = ClassicSettings()
        let user = (try? UserStore.defaultURL(folder: "Biblia Clásica")).flatMap { try? UserStore(path: $0.path) }
        model = ReaderModel(settings: settings, user: user)
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
        let wc = MainWindowController(model: model, settings: settings)
        main = wc
        wc.showWindow(nil)
        wc.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        model.announceInitial()
        wc.reader.focusReader()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) { model?.persist() }

    // MARK: actions

    @objc func showPreferences(_ sender: Any?) {
        if prefs == nil { prefs = PreferencesWindowController(settings: settings, model: model) }
        prefs?.show()
    }
    @objc func gotoReference(_ sender: Any?) { main?.window?.makeKeyAndOrderFront(nil); main?.focusGoto() }
    @objc func copyWithReference(_ sender: Any?) { main?.reader.copyWithReference() }
    @objc func prevChapter(_ sender: Any?) { model.goPrev() }
    @objc func nextChapter(_ sender: Any?) { model.goNext() }
    @objc func fontLarger(_ sender: Any?) { settings.stepFont(1) }
    @objc func fontSmaller(_ sender: Any?) { settings.stepFont(-1) }
    @objc func fontReset(_ sender: Any?) { settings.resetFont() }
    @objc func pickTheme(_ sender: NSMenuItem) { if let t = ThemeChoice(rawValue: sender.representedObject as? String ?? "") { settings.theme = t } }
    @objc func pickLayout(_ sender: NSMenuItem) { if let l = VerseLayout(rawValue: sender.representedObject as? String ?? "") { settings.layout = l } }
    @objc func toggleHeadings(_ sender: Any?) { settings.showHeadings.toggle() }
    @objc func focusFilter(_ sender: Any?) { main?.sidebar.focusFilter() }

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
        case #selector(toggleHeadings(_:)):
            item.state = settings.showHeadings ? .on : .off
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
        _ = add(edit, "Copiar", #selector(NSText.copy(_:)), "c", target: nil)
        _ = add(edit, "Pegar", #selector(NSText.paste(_:)), "v", target: nil)
        _ = add(edit, "Copiar con referencia", #selector(copyWithReference(_:)), "c", [.command, .option])
        _ = add(edit, "Seleccionar todo", #selector(NSText.selectAll(_:)), "a", target: nil)
        edit.addItem(.separator())
        _ = add(edit, "Ir a referencia…", #selector(gotoReference(_:)), "l")
        _ = add(edit, "Filtrar libros", #selector(focusFilter(_:)), "f", [.command, .option])

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
