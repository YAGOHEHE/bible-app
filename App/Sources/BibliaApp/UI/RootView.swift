import BibliaCore
import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var state
    @Environment(SearchModel.self) private var search

    var body: some View {
        switch state.load {
        case .loading:
            ProgressView().frame(minWidth: 800, minHeight: 500)
        case .missingData:
            ContentUnavailableView("Datos no encontrados", systemImage: "books.vertical",
                                   description: Text("No se encontró bible.sqlite dentro de la aplicación."))
                .frame(minWidth: 800, minHeight: 500)
        case .failed(let msg):
            ContentUnavailableView("Error al abrir los datos", systemImage: "exclamationmark.triangle",
                                   description: Text(msg)).frame(minWidth: 800, minHeight: 500)
        case .ready:
            NavigationSplitView {
                VStack(spacing: 0) {
                    SidebarModeBar()
                    if search.active { SearchPanel() }
                    else if state.showNotesPanel { NotesPanel() }
                    else { BookSidebar() }
                }
                .frame(maxHeight: .infinity, alignment: .top)
                .navigationSplitViewColumnWidth(min: 220, ideal: 300, max: 460)
            } detail: {
                Group { if state.parallelOn { ParallelView() } else { ReaderView() } }
                    .inspector(isPresented: Binding(get: { state.showInspector }, set: { state.showInspector = $0 })) {
                        InspectorView().inspectorColumnWidth(min: 260, ideal: 320, max: 440)
                    }
            }
            .navigationTitle("\(state.bookName(state.book)) \(state.chapter)")
            .navigationSubtitle(state.glossMode
                                ? ([state.translationId] + state.glossSet.effective(primary: state.translationId)).joined(separator: " · ")
                                : state.parallelOn && state.parallelColumns.count > 1
                                ? state.parallelColumns.map(\.id).joined(separator: " · ")
                                : (state.currentTranslation?.name ?? state.translationId))
            .frame(minWidth: 800, minHeight: 500)
            .overlay(alignment: .top) {
                if state.showGoto { GotoBar().transition(.opacity) }
            }
            .toolbar { ReaderToolbar() }
            .sheet(isPresented: Binding(get: { state.showVersions }, set: { state.showVersions = $0 })) {
                VersionManagerView()
            }
            .sheet(isPresented: Binding(get: { state.showHistory }, set: { state.showHistory = $0 })) {
                HistoryView()
            }
        }
    }
}

struct ReaderToolbar: ToolbarContent {
    @Environment(AppState.self) private var state
    @Environment(AppSettings.self) private var settings
    @Environment(\.theme) private var theme

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button { state.goPrev() } label: { Image(systemName: "chevron.left") }
                .help(state.prevPosition.map { "Capítulo anterior, \(state.bookName($0.book)) \($0.chapter)" } ?? "Principio de la Biblia")
                .disabled(!state.canGoPrev)
                .accessibilityLabel(state.prevPosition.map { "Capítulo anterior, \(state.bookName($0.book)) \($0.chapter)" } ?? "Capítulo anterior")
            Button { state.goNext() } label: { Image(systemName: "chevron.right") }
                .help(state.nextPosition.map { "Siguiente, \(state.bookName($0.book)) \($0.chapter)" } ?? "Final de la Biblia")
                .disabled(!state.canGoNext)
                .accessibilityLabel(state.nextPosition.map { "Siguiente, \(state.bookName($0.book)) \($0.chapter)" } ?? "Siguiente")
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button { state.showGoto = true } label: { Image(systemName: "arrow.turn.down.right") }
                .help("Ir a referencia (⌘L)")
                .accessibilityLabel("Ir a referencia")
            Picker("Versión", selection: Binding(get: { state.translationId }, set: { state.setTranslation($0) })) {
                ForEach(state.translations) { Text($0.id).tag($0.id) }
            }
            .pickerStyle(.menu)
            .help("Versión de la Biblia")
            Button { state.toggleParallel() } label: {
                Image(systemName: "rectangle.split.2x1")
                    .foregroundStyle(state.parallelOn ? theme.palette.accent : theme.palette.textSecondary)
            }
            .help("Vista paralela (⌘\\)")
            .accessibilityLabel("Vista paralela, \(state.parallelOn ? "activada" : "desactivada")")
            if state.parallelOn {
                Picker("Disposición", selection: Binding(get: { state.parallelLayout }, set: { state.setParallelLayout($0) })) {
                    ForEach(ParallelLayout.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.menu).help("Columnas o intercalado")
                if state.parallelLayout == .interleaved { GlossMenu() }
            }
            Button { state.toggleStrongMode() } label: {
                Image(systemName: "textformat.abc.dottedunderline")
                    .foregroundStyle(state.strongMode && state.strongAvailable ? theme.palette.accent : theme.palette.textSecondary)
            }
            .disabled(!state.strongAvailable)
            .help(state.strongAvailable ? "Modo Strong (⌥⌘S)" : "Esta versión no tiene números Strong")
            .accessibilityLabel("Modo Strong, \(state.strongMode && state.strongAvailable ? "activado" : "desactivado")")
            Button { state.toggleInspector() } label: { Image(systemName: "sidebar.right") }
                .help("Inspector Strong (⌘I)").accessibilityLabel("Panel lateral: Strong, nota y referencias")
            Button { state.showHistory = true } label: { Image(systemName: "clock.arrow.circlepath") }
                .help("Historial (⌘Y)").accessibilityLabel("Historial")
            Button { state.showVersions = true } label: { Image(systemName: "books.vertical") }
                .help("Gestor de versiones (⌥⌘V)").accessibilityLabel("Gestor de versiones")
            Button { settings.stepFont(-1) } label: { Image(systemName: "textformat.size.smaller") }
                .help("Reducir tamaño (⌘−)").accessibilityLabel("Reducir tamaño de letra")
                .disabled(settings.fontScale <= FontScale.min + 0.001)
            Button { settings.stepFont(1) } label: { Image(systemName: "textformat.size.larger") }
                .help("Aumentar tamaño (⌘+)").accessibilityLabel("Aumentar tamaño de letra")
                .disabled(settings.fontScale >= FontScale.max - 0.001)
        }
    }
}
