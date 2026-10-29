import SwiftUI

@main
struct BibliaApp: App {
    @State private var settings: AppSettings
    @State private var state: AppState
    @State private var search: SearchModel

    init() {
        let s = AppSettings()
        _settings = State(initialValue: s)
        let st = AppState(settings: s)
        _state = State(initialValue: st)
        _search = State(initialValue: SearchModel(state: st))
    }

    var body: some Scene {
        WindowGroup {
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

        Settings {
            SettingsView()
                .environment(state)
                .environment(settings)
                .themedRoot(settings)
        }
    }
}

extension BibliaApp {
    /// Argumentos de arranque (`open -a BibliaApp --args -startSearch 永生 -startGoto 约3:16`):
    /// NSUserDefaults los lee del dominio de argumentos. Útil para capturas y pruebas manuales.
    @MainActor private func applyLaunchArguments() {
        guard state.load == .ready else { return }
        let d = UserDefaults.standard
        if let t = d.string(forKey: "startTranslation") { state.setTranslation(t) }
        if let q = d.string(forKey: "startGoto") { state.goTo(q) }
        if let q = d.string(forKey: "startSearch") {
            search.start(q)
            if d.bool(forKey: "startSearchOpenFirst") { Task { await search.run(); search.open(index: 0) } }
        }
    }
}

struct ReaderCommands: Commands {
    let state: AppState
    let settings: AppSettings
    let search: SearchModel

    var body: some Commands {
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
            Button("Versiones…") { state.showVersions = true }
                .keyboardShortcut("v", modifiers: [.command, .option])
            Divider()
            Button("Copiar con referencia") { state.copyWithReference() }
                .keyboardShortcut("c", modifiers: [.command, .option]).disabled(!state.canCopyReference)
        }
    }
}
