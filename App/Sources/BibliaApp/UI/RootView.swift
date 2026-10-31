import BibliaCore
import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var state
    @Environment(SearchModel.self) private var search
    @State private var columns: NavigationSplitViewVisibility = .all

    var body: some View {
        switch state.load {
        case .loading:
            ProgressView().frame(minWidth: 560, minHeight: 500)
        case .missingData:
            ContentUnavailableView("Datos no encontrados", systemImage: "books.vertical",
                                   description: Text("No se encontró bible.sqlite dentro de la aplicación."))
                .frame(minWidth: 560, minHeight: 500)
        case .failed(let msg):
            ContentUnavailableView("Error al abrir los datos", systemImage: "exclamationmark.triangle",
                                   description: Text(msg)).frame(minWidth: 560, minHeight: 500)
        case .ready:
            NavigationSplitView(columnVisibility: $columns) {
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
            .frame(minWidth: 560, minHeight: 500)
            // Ventana estrecha (< 720 pt): la barra lateral se oculta sola para dejar sitio al lector; se vuelve a
            // mostrar con su botón o al ensanchar la ventana.
            .background(GeometryReader { g in
                Color.clear.onChange(of: RootLayout.sidebarVisibility(windowWidth: g.size.width), initial: true) { _, v in
                    columns = v
                }
            })
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

/// Etiqueta de los conmutadores de la barra («Paralelo», «Strong»): activo = fondo acento al 12 % y texto acento.
struct ToolbarToggleLabel: View {
    @Environment(\.theme) private var theme
    let icon: String?
    let glyph: String?
    let title: String
    let active: Bool

    var body: some View {
        HStack(spacing: 5) {
            if let icon { Image(systemName: icon).font(.system(size: 12)) }
            if let glyph { Text(glyph).font(theme.serifFont(size: 14, weight: .medium)) }
            Text(title).font(theme.uiFont(size: 12, weight: .medium))
        }
        .foregroundStyle(active ? theme.palette.accent : theme.palette.textSecondary)
        .padding(.horizontal, 9).padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 6).fill(active ? theme.palette.accent.opacity(0.12) : Color.clear))
        .contentShape(RoundedRectangle(cornerRadius: 6))
    }
}

/// Botón ancho con la referencia actual y la pista ⌘L; abre «Ir a referencia».
struct ReferenceButton: View {
    @Environment(AppState.self) private var state
    @Environment(\.theme) private var theme

    var body: some View {
        Button { state.showGoto = true } label: {
            HStack(spacing: 10) {
                Text("\(state.bookName(state.book)) \(state.chapter)")
                    .font(theme.uiFont(size: 13, weight: .semibold))
                    .foregroundStyle(theme.palette.textPrimary).lineLimit(1)
                Spacer(minLength: 6)
                Text("⌘L").font(theme.uiFont(size: 11)).foregroundStyle(theme.palette.textMuted)
            }
            .padding(.horizontal, 10).padding(.vertical, 4)
            .frame(minWidth: 120, idealWidth: 170, maxWidth: 200)
            .background(RoundedRectangle(cornerRadius: 7).fill(theme.palette.surface))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(theme.palette.border, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Ir a referencia (⌘L)")
        .accessibilityLabel("Ir a referencia, \(state.bookName(state.book)) \(state.chapter)")
    }
}

/// «Aa»: tema y tamaño de letra en un popover.
struct AaButton: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.theme) private var theme
    @State private var open = false

    var body: some View {
        @Bindable var s = settings
        Button { open.toggle() } label: {
            Text("Aa").font(theme.uiFont(size: 13, weight: .semibold))
                .foregroundStyle(open ? theme.palette.accent : theme.palette.textSecondary)
                .padding(.horizontal, 6).padding(.vertical, 3)
        }
        .buttonStyle(.plain)
        .help("Apariencia: tema y tamaño de letra")
        .accessibilityLabel("Apariencia y tamaño de letra")
        .popover(isPresented: $open, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Tema").font(theme.uiFont(size: 11, weight: .semibold)).foregroundStyle(theme.palette.textMuted)
                Picker("Tema", selection: $s.themeChoice) {
                    ForEach(ThemeChoice.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden()
                .accessibilityLabel("Tema de la aplicación")
                Text("Tamaño").font(theme.uiFont(size: 11, weight: .semibold)).foregroundStyle(theme.palette.textMuted)
                HStack(spacing: 12) {
                    Button { settings.stepFont(-1) } label: { Image(systemName: "minus").frame(width: 26, height: 22) }
                        .disabled(settings.fontScale <= FontScale.min + 0.001)
                        .help("Reducir tamaño (⌘−)").accessibilityLabel("Reducir tamaño de letra")
                    Text("\(Int((settings.fontScale * 100).rounded())) %")
                        .font(theme.uiFont(size: 13, weight: .medium)).monospacedDigit()
                        .frame(minWidth: 52)
                        .accessibilityLabel("Tamaño de letra \(Int((settings.fontScale * 100).rounded())) por ciento")
                    Button { settings.stepFont(1) } label: { Image(systemName: "plus").frame(width: 26, height: 22) }
                        .disabled(settings.fontScale >= FontScale.max - 0.001)
                        .help("Aumentar tamaño (⌘+)").accessibilityLabel("Aumentar tamaño de letra")
                }
                .frame(maxWidth: .infinity)
            }
            .padding(16).frame(width: 280)
        }
    }
}

/// Barra de herramientas «Códice». Historial (⌘Y) y Versiones (⌥⌘V) viven en el menú «Leer» (ReaderCommands).
/// El menú «Glosas» (modo intercalado) va junto al segmentado «Columnas | Intercalado».
struct ReaderToolbar: ToolbarContent {
    @Environment(AppState.self) private var state
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
        ToolbarItem(placement: .principal) {
            HStack(spacing: 8) {
                ReferenceButton()
                Menu {
                    Picker("Versión", selection: Binding(get: { state.translationId }, set: { state.setTranslation($0) })) {
                        ForEach(state.translations) { Text("\($0.id) · \($0.name)").tag($0.id) }
                    }
                    .pickerStyle(.inline).labelsHidden()
                } label: {
                    Text(state.translationId).font(theme.uiFont(size: 13, weight: .semibold))
                        .foregroundStyle(theme.palette.accent)
                }
                .menuStyle(.borderlessButton).fixedSize()
                .help("Versión de la Biblia")
                .accessibilityLabel("Versión de la Biblia, \(state.translationId)")
            }
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button { state.toggleParallel() } label: {
                ToolbarToggleLabel(icon: "rectangle.split.2x1", glyph: nil, title: "Paralelo", active: state.parallelOn)
            }
            .buttonStyle(.plain)
            .help("Vista paralela (⌘\\)")
            .accessibilityLabel("Vista paralela, \(state.parallelOn ? "activada" : "desactivada")")
            if state.parallelOn {
                Picker("Disposición", selection: Binding(get: { state.parallelLayout }, set: { state.setParallelLayout($0) })) {
                    ForEach(ParallelLayout.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
                .help("Columnas o intercalado")
                .accessibilityLabel("Disposición de la vista paralela")
                if state.parallelLayout == .interleaved { GlossMenu() }
            }
            Button { state.toggleStrongMode() } label: {
                ToolbarToggleLabel(icon: nil, glyph: "α", title: "Strong", active: state.strongMode && state.strongAvailable)
            }
            .buttonStyle(.plain)
            .disabled(!state.strongAvailable)
            .opacity(state.strongAvailable ? 1 : 0.4)
            .help(state.strongAvailable ? "Modo Strong (⌥⌘S)" : "Esta versión no tiene números Strong")
            .accessibilityLabel("Modo Strong, \(state.strongMode && state.strongAvailable ? "activado" : "desactivado")")
            AaButton()
            Button { state.toggleInspector() } label: { Image(systemName: "sidebar.right") }
                .help("Inspector Strong (⌘I)").accessibilityLabel("Panel lateral: Strong, nota y referencias")
        }
    }
}

enum RootLayout {
    static let autoHideSidebarBelow: CGFloat = 720
    static func sidebarVisibility(windowWidth: CGFloat) -> NavigationSplitViewVisibility {
        windowWidth < autoHideSidebarBelow ? .detailOnly : .all
    }
}
