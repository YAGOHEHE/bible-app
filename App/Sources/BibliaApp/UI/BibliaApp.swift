import BibliaCore
import SwiftUI

@main
struct BibliaApp: App {
    @State private var settings: AppSettings
    @State private var state: AppState
    @State private var search: SearchModel

    init() {
        LegacyMigration.runAtLaunch()
        let s = AppSettings()
        _settings = State(initialValue: s)
        let st = AppState(settings: s)
        _state = State(initialValue: st)
        _search = State(initialValue: SearchModel(state: st))
    }

    var body: some Scene {
        WindowGroup("Biblia") {
            RootView()
                .environment(state)
                .environment(search)
                .environment(settings)
                .themedRoot(settings)
                .task {
                    state.bootstrap()
                    applyLaunchArguments()
                }
        }
        .defaultSize(width: 1280, height: 820)
        .commands { ReaderCommands(state: state, settings: settings, search: search) }

        Window("Acerca de Biblia", id: "about") {
            AboutView().environment(state)
        }
        .windowResizability(.contentSize)

        Settings {
            SettingsView()
                .environment(state)
                .environment(settings)
                .themedRoot(settings)
        }
    }
}

extension BibliaApp {
    /// Argumentos de arranque (`open -a Biblia --args -startSearch 永生 -startGoto 约3:16`):
    /// NSUserDefaults los lee del dominio de argumentos. Útil para capturas y pruebas manuales.
    @MainActor private func applyLaunchArguments() {
        guard state.load == .ready else { return }
        let d = UserDefaults.standard
        if let t = d.string(forKey: "startTranslation") { state.setTranslation(t) }
        if let q = d.string(forKey: "startGoto") { state.goTo(q) }
        if d.object(forKey: "strongMode") != nil { state.setStrongMode(d.bool(forKey: "strongMode")) }
        if let id = d.string(forKey: "openStrong") {
            state.strongSelection = state.strongSpans.sorted { $0.key < $1.key }.lazy.flatMap { v, ss in ss.map { (v, $0) } }
                .first { $0.1.strong == id }.map { StrongSelection(strong: id, verse: $0.0, start: $0.1.start) }
            state.strongWord = state.strongSelection.flatMap { s in state.strongSpans[s.verse]?.first { $0.start == s.start }?.word }
            state.showStrong(id)
        }
        if d.bool(forKey: "showHistory") { state.showHistory = true }
        applyAnnotationArguments(d)
        applyNoteArguments(d)
        // Ganchos solo para pruebas manuales (replica/test-plan.md).
        if d.object(forKey: "startParallel") != nil { state.setParallel(d.bool(forKey: "startParallel")) }
        if let l = d.string(forKey: "startParallelLayout").flatMap(ParallelLayout.init(rawValue:)) { state.setParallelLayout(l) }
        if let g = d.string(forKey: "glosses") {
            state.setGlosses(g.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
        }
        if d.bool(forKey: "showVersions") { state.showVersions = true }
        if d.double(forKey: "windowWidth") > 0, let w = NSApp.windows.first {
            w.setContentSize(NSSize(width: d.double(forKey: "windowWidth"), height: d.double(forKey: "windowHeight") > 0 ? d.double(forKey: "windowHeight") : 700))
        }
        if let q = d.string(forKey: "startSearch") {
            search.start(q)
            if d.bool(forKey: "startSearchOpenFirst") { Task { await search.run(); search.open(index: 0) } }
        }
    }
}

extension BibliaApp {
    /// `-annotate "3:yellow,5:green,16:blue,18:bookmark,20:note"` crea anotaciones reales en el almacén de usuario;
    /// `-selectVerse 16` (o `16-18`) selecciona y muestra la barra de acciones. Solo para capturas y pruebas manuales.
    @MainActor private func applyAnnotationArguments(_ d: UserDefaults) {
        if let spec = d.string(forKey: "annotate") {
            for item in spec.split(separator: ",") {
                let kv = item.split(separator: ":").map(String.init)
                guard kv.count == 2, let v = Int(kv[0]) else { continue }
                if kv[1] == "note" {
                    _ = try? state.annotations?.addNote(book: state.book, chapter: state.chapter, verseStart: v, body: "Nota de ejemplo")
                    state.reloadAnnotations()
                } else if kv[1] == "bookmark" { state.toggleBookmarkSelection(scope: [v]) }
                else if let c = HighlightColor(rawValue: kv[1]) { state.highlightSelection(c, scope: [v]) }
            }
        }
        if let sel = d.string(forKey: "selectVerse") {
            let r = sel.split(separator: "-").compactMap { Int($0) }
            guard let a = r.first else { return }
            let b = r.count > 1 ? r[1] : a
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 900_000_000)
                state.clickVerse(a, shift: false, command: false)
                if b > a { state.selectedVerses = Set(a...b) }
                state.actionBarVerse = a
                state.actionBarVisible = true
            }
        }
    }
}

struct ReaderCommands: Commands {
    let state: AppState
    let settings: AppSettings
    let search: SearchModel
    @Environment(\.openWindow) private var openWindow

    /// ⌘C: texto seleccionado en un campo; si no, los versículos seleccionados; si no, copia estándar.
    @MainActor static func copy(_ state: AppState) {
        if let tv = NSApp.keyWindow?.firstResponder as? NSTextView, tv.selectedRange().length > 0 {
            tv.copy(nil)
        } else if state.isEnabled(.copy) {
            state.perform(.copy)
        } else {
            NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil)
        }
    }

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("Acerca de Biblia") { openWindow(id: "about") }
        }
        CommandGroup(replacing: .pasteboard) {
            Button("Cortar") { NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil) }
                .keyboardShortcut("x", modifiers: .command)
            Button("Copiar") { ReaderCommands.copy(state) }
                .keyboardShortcut("c", modifiers: .command)
            Button("Pegar") { NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil) }
                .keyboardShortcut("v", modifiers: .command)
            Button("Seleccionar todo") { NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil) }
                .keyboardShortcut("a", modifiers: .command)
        }
        CommandMenu("Versículo") {
            Button("Copiar con referencia") { state.perform(.copyReference) }
                .keyboardShortcut("c", modifiers: [.command, .option]).disabled(!state.isEnabled(.copyReference))
            Button("Deseleccionar todo") { state.clearSelection() }
                .keyboardShortcut("a", modifiers: [.command, .shift]).disabled(state.selectedVerses.isEmpty)
            Divider()
            Button("Resaltar con el último color") { state.perform(.highlight) }
                .keyboardShortcut("h", modifiers: [.command, .option]).disabled(!state.isEnabled(.highlight))
            Menu("Resaltar con") {
                ForEach(HighlightColor.allCases) { c in
                    Button(c.displayName) { state.highlightSelection(c) }
                }
                Divider()
                Button("Quitar resaltado") { state.removeHighlightSelection() }
                    .disabled(!state.selectionHasHighlight())
            }
            .disabled(!state.isEnabled(.highlight))
            Button("Anotar") { state.perform(.note) }
                .keyboardShortcut("n", modifiers: [.command, .option]).disabled(!state.isEnabled(.note))
            Button(state.selectionBookmarked() ? "Quitar marcador" : "Marcador") { state.perform(.bookmark) }
                .keyboardShortcut("d", modifiers: .command).disabled(!state.isEnabled(.bookmark))
            Divider()
            Button("Referencias cruzadas") { state.perform(.crossRefs) }.disabled(!state.isEnabled(.crossRefs))
            Button("Comparar versiones") { state.perform(.compare) }.disabled(!state.isEnabled(.compare))
            Button("Abrir en Strong") { state.perform(.strong) }.disabled(!state.isEnabled(.strong))
        }
        CommandMenu("Buscar") {
            Button("Buscar…") { search.activate() }
                .keyboardShortcut("f", modifiers: .command)
            Button("Ir a referencia…") { state.showGoto = true }
                .keyboardShortcut("l", modifiers: .command)
            Divider()
            Button("Siguiente coincidencia") { search.next() }
                .keyboardShortcut("g", modifiers: .command).disabled(search.hits.isEmpty)
            Button("Coincidencia anterior") { search.previous() }
                .keyboardShortcut("g", modifiers: [.command, .shift]).disabled(search.hits.isEmpty)
            Button("Quitar resaltado") { state.clearSearchHighlight() }
                .disabled(state.searchTerms.isEmpty)
        }
        CommandMenu("Leer") {
            Button("Capítulo anterior") { state.goPrev() }
                .keyboardShortcut("[", modifiers: .command).disabled(!state.canGoPrev)
            Button("Capítulo siguiente") { state.goNext() }
                .keyboardShortcut("]", modifiers: .command).disabled(!state.canGoNext)
            Divider()
            Button("Aumentar tamaño") { settings.stepFont(1) }
                .keyboardShortcut("+", modifiers: .command).disabled(settings.fontScale >= FontScale.max - 0.001)
            Button("Aumentar tamaño (=)") { settings.stepFont(1) }
                .keyboardShortcut("=", modifiers: .command)
            Button("Reducir tamaño") { settings.stepFont(-1) }
                .keyboardShortcut("-", modifiers: .command).disabled(settings.fontScale <= FontScale.min + 0.001)
            Button("Tamaño real") { settings.resetFont() }
                .keyboardShortcut("0", modifiers: .command)
            Divider()
            Button(state.parallelOn ? "Desactivar vista paralela" : "Vista paralela") { state.toggleParallel() }
                .keyboardShortcut("\\", modifiers: .command)
            Button(state.showGlosses ? "Ocultar glosas" : "Mostrar glosas") { state.toggleShowGlosses() }
                .keyboardShortcut("g", modifiers: [.command, .option]).disabled(!state.glossMode)
            Button("Versiones…") { state.showVersions = true }
                .keyboardShortcut("v", modifiers: [.command, .option])
            Divider()
            Button(state.strongMode ? "Desactivar modo Strong" : "Modo Strong") { state.toggleStrongMode() }
                .keyboardShortcut("s", modifiers: [.command, .option]).disabled(!state.strongAvailable)
            Button(state.showInspector ? "Ocultar inspector Strong" : "Inspector Strong") { state.toggleInspector() }
                .keyboardShortcut("i", modifiers: .command)
            Button("Historial…") { state.showHistory = true }
                .keyboardShortcut("y", modifiers: .command)
        }
    }
}

extension BibliaApp {
    /// `-openNote "Rom 8:28"` (crea una nota de ejemplo si no hay y abre la pestaña Nota; `-notePreview 1` muestra la vista
    /// previa), `-showRefs "John 3:16"` (pestaña Referencias), `-sidebar notes|search|books`. Solo capturas y pruebas manuales.
    @MainActor private func applyNoteArguments(_ d: UserDefaults) {
        func resolve(_ text: String) -> BibleRef? {
            if case .success(let r) = GotoResolver.resolve(text, chapterCounts: state.chapterCounts) { return r }
            return nil
        }
        if let t = d.string(forKey: "openNote"), let ref = resolve(t), let a = ref.verseFrom {
            let b = ref.verseTo ?? a
            state.navigate(to: ref)
            if (try? state.annotations?.chapter(book: ref.book, chapter: ref.chapter).notes.contains { $0.overlaps(a...b) }) != true {
                _ = try? state.annotations?.addNote(book: ref.book, chapter: ref.chapter, verseStart: a, verseEnd: b, body: """
                    **Todo coopera para bien**
                    Ver también *Gn 50:20* y [Rom 5:3-5](https://example.org).

                    - Dios obra en *todas* las cosas
                    - Para los que le aman
                    """)
                state.reloadAnnotations()
            }
            state.noteEditor.preview = d.bool(forKey: "notePreview")
            state.beginNote(for: a...b)
        }
        if let t = d.string(forKey: "showRefs"), let ref = resolve(t), let a = ref.verseFrom {
            state.navigate(to: ref)
            state.showCrossRefs(for: a...(ref.verseTo ?? a))
        }
        switch d.string(forKey: "sidebar") {
        case "notes": search.deactivate(); state.showNotesPanel = true
        case "search": search.activate()
        case "books": search.deactivate(); state.showNotesPanel = false
        default: break
        }
    }
}
