import SwiftUI

@main
struct BibliaApp: App {
    @State private var settings: AppSettings
    @State private var state: AppState

    init() {
        let s = AppSettings()
        _settings = State(initialValue: s)
        _state = State(initialValue: AppState(settings: s))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(state)
                .environment(settings)
                .themedRoot(settings)
                .task { state.bootstrap() }
        }
        .defaultSize(width: 1280, height: 820)
        .commands { ReaderCommands(state: state, settings: settings) }

        Settings {
            SettingsView()
                .environment(state)
                .environment(settings)
                .themedRoot(settings)
        }
    }
}

struct ReaderCommands: Commands {
    let state: AppState
    let settings: AppSettings

    var body: some Commands {
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
