import BibliaCore
import SwiftUI

/// Selector de la barra lateral: Libros (S02) | Buscar (S05) | Notas.
struct SidebarModeBar: View {
    @Environment(AppState.self) private var state
    @Environment(SearchModel.self) private var search

    private enum Mode { case books, search, notes }

    var body: some View {
        let mode = Binding<Mode>(
            get: { search.active ? .search : state.showNotesPanel ? .notes : .books },
            set: { m in
                switch m {
                case .books: search.deactivate(); state.showNotesPanel = false
                case .search: search.activate()
                case .notes: search.deactivate(); state.showNotesPanel = true
                }
            })
        Picker("Barra lateral", selection: mode) {
            Label("Libros", systemImage: "books.vertical").tag(Mode.books)
            Label("Buscar", systemImage: "magnifyingglass").tag(Mode.search)
            Label("Notas", systemImage: "square.and.pencil").tag(Mode.notes)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal, 10).padding(.top, 8)
        .help("Libros, búsqueda (⌘F) o notas")
        .accessibilityLabel("Modo de la barra lateral")
    }
}

/// S05: campo de búsqueda, opciones, historial y resultados agrupados por libro.
struct SearchPanel: View {
    @Environment(AppState.self) private var state
    @Environment(SearchModel.self) private var search
    @Environment(\.theme) private var theme
    @FocusState private var fieldFocused: Bool

    var body: some View {
        @Bindable var m = search
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Buscar · amor/gracia = o", text: $m.query)
                    .textFieldStyle(.plain)
                    .focused($fieldFocused)
                    .onSubmit { search.runNow() }
                    .onKeyPress(.escape) {
                        if search.query.isEmpty { search.deactivate() } else { search.query = "" }
                        return .handled
                    }
                    .help("Escribe una palabra o frase. Usa «/» para buscar alternativas: amor/gracia. Distingue acentos.")
                    .accessibilityLabel("Buscar en la Biblia")
                if !search.query.isEmpty {
                    Button { search.query = ""; fieldFocused = true } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("Borrar búsqueda")
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary.opacity(0.5)))
            .padding(.horizontal, 10).padding(.top, 8).padding(.bottom, 6)

            options
            Divider()
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .onAppear { fieldFocused = true; search.loadHistory() }
        .onChange(of: search.focusToken) { _, _ in fieldFocused = true }
        .onChange(of: search.query) { _, _ in search.scheduleSearch() }
        .onChange(of: search.scope) { _, _ in search.scheduleSearch() }
        .onChange(of: search.translationOverride) { _, _ in search.scheduleSearch() }
        .onChange(of: state.translationId) { _, _ in search.scheduleSearch() }
        .onChange(of: state.book) { _, _ in if search.scope == .book { search.scheduleSearch() } }
    }

    private var options: some View {
        @Bindable var m = search
        return HStack(spacing: 6) {
            Picker("Versión", selection: Binding(get: { search.translationId }, set: { search.translationOverride = $0 })) {
                ForEach(state.translations) { Text($0.id).tag($0.id) }
            }
            .pickerStyle(.menu).fixedSize().labelsHidden()
            .help("Versión en la que buscar")
            Picker("Alcance", selection: $m.scope) {
                ForEach(SearchScopeChoice.allCases) {
                    Text($0 == .book ? "Libro actual: \(state.bookName(state.book))" : $0.label).tag($0)
                }
            }
            .pickerStyle(.menu).labelsHidden()
            .help("Dónde buscar")
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10).padding(.bottom, 6)
    }

    @ViewBuilder private var content: some View {
        switch search.phase {
        case .idle:
            SearchIdleView()
        case .loading:
            VStack { Spacer(); ProgressView("Buscando…"); Spacer() }.frame(maxWidth: .infinity)
        case .empty:
            VStack(spacing: 0) {
            ContentUnavailableView("Sin resultados para «\(search.trimmedQuery)»", systemImage: "magnifyingglass",
                                   description: Text("No hay coincidencias en \(search.translationId). Prueba otra palabra, otra versión o amplía el alcance."))
            if let sg = search.suggestion {
                VStack(spacing: 6) {
                    Text(sg.message(query: search.trimmedQuery, current: search.translationId))
                        .font(.callout).multilineTextAlignment(.center)
                    Button("Buscar en \(sg.translationId)") { search.applySuggestion() }
                }
                .padding(12)
                .accessibilityElement(children: .contain)
            }
            }
        case .failed(let msg):
            ContentUnavailableView("La búsqueda ha fallado", systemImage: "exclamationmark.triangle",
                                   description: Text(msg))
        case .results:
            SearchResultsList()
        }
    }
}

private struct SearchIdleView: View {
    @Environment(SearchModel.self) private var search

    var body: some View {
        List {
            if search.history.isEmpty {
                Section {
                    Text("Escribe al menos un carácter. Con «/» buscas alternativas (amor/gracia). La búsqueda distingue acentos pero no mayúsculas.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            } else {
                Section {
                    ForEach(search.history, id: \.self) { q in
                        Button { search.start(q) } label: {
                            Label(q, systemImage: "clock.arrow.circlepath").lineLimit(1)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Buscar de nuevo \(q)")
                    }
                } header: {
                    HStack {
                        Text("Búsquedas recientes")
                        Spacer()
                        Button("Borrar historial") { search.clearHistory() }
                            .buttonStyle(.link).font(.caption)
                    }
                }
            }
        }
        .listStyle(.plain)
    }
}

private struct SearchResultsList: View {
    @Environment(AppState.self) private var state
    @Environment(SearchModel.self) private var search
    @Environment(\.theme) private var theme

    var body: some View {
        let groups = search.groups
        VStack(spacing: 0) {
            HStack {
                Text(summary).font(.caption).foregroundStyle(.secondary)
                    .accessibilityLabel(summary)
                Spacer()
            }
            .padding(.horizontal, 12).padding(.vertical, 5)
            ScrollViewReader { proxy in
                List {
                    ForEach(groups) { g in
                        Section {
                            ForEach(g.hits) { h in
                                ResultRow(hit: h, terms: search.terms, selected: isSelected(h))
                                    .id(h.id)
                                    .listRowInsets(EdgeInsets(top: 0, leading: 6, bottom: 0, trailing: 6))
                                    .listRowSeparator(.hidden)
                            }
                        } header: {
                            HStack {
                                Text(state.bookName(g.book)).fontWeight(.semibold)
                                Spacer()
                                Text("\(g.count)").monospacedDigit()
                            }
                            .font(.caption).foregroundStyle(.secondary)
                            .accessibilityElement(children: .combine)
                        }
                    }
                    if search.hasMore {
                        Button("Mostrar más (\(search.hits.count) de \(search.total))") { search.showMore() }
                            .frame(maxWidth: .infinity)
                    }
                }
                .listStyle(.plain)
                .onChange(of: search.selected) { _, i in
                    if let i, let h = search.hits[safe: i] { withAnimation { proxy.scrollTo(h.id) } }
                }
            }
        }
    }

    private var summary: String {
        let n = search.total
        let noun = n == 1 ? "resultado" : "resultados"
        let shown = search.hasMore ? " · mostrando \(search.hits.count)" : ""
        return "\(n) \(noun) en \(search.translationId)\(shown)"
    }

    private func isSelected(_ h: SearchHit) -> Bool {
        guard let i = search.selected, let s = search.hits[safe: i] else { return false }
        return s.id == h.id
    }
}

private struct ResultRow: View {
    @Environment(AppState.self) private var state
    @Environment(SearchModel.self) private var search
    @Environment(\.theme) private var theme
    let hit: SearchHit
    let terms: [String]
    let selected: Bool

    var body: some View {
        let ref = "\(state.bookName(hit.book)) \(hit.chapter):\(hit.verse)"
        Button {
            if let i = search.hits.firstIndex(where: { $0.id == hit.id }) { search.open(index: i) }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(ref).font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.palette.textPrimary)
                Text(Self.attributed(hit.text, terms: terms, theme: theme))
                    .font(.system(size: 13)).lineLimit(3)
                    .foregroundStyle(theme.palette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 6).padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 6).fill(selected ? theme.palette.selection : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(ref). \(hit.text)")
        .accessibilityHint("Abre el versículo en el lector")
    }

    static func attributed(_ text: String, terms: [String], theme: Theme) -> AttributedString {
        let shown = SearchHighlighter.window(text, terms: terms)
        var a = AttributedString(shown)
        for r in SearchHighlighter.ranges(in: shown, terms: terms) {
            if let lo = AttributedString.Index(r.lowerBound, within: a), let hi = AttributedString.Index(r.upperBound, within: a) {
                a[lo..<hi].backgroundColor = theme.palette.searchHighlight
                a[lo..<hi].foregroundColor = theme.palette.textPrimary
            }
        }
        return a
    }
}

/// Aviso en el lector: las coincidencias de la búsqueda están resaltadas; ✕ las quita.
struct SearchTermsChip: View {
    @Environment(AppState.self) private var state
    @Environment(\.theme) private var theme

    var body: some View {
        if !state.searchTerms.isEmpty {
            HStack(spacing: 6) {
                Text("Coincidencias: \(state.searchTerms.map { "«\($0)»" }.joined(separator: " "))")
                    .font(.caption).lineLimit(1)
                Button { state.clearSearchHighlight() } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).accessibilityLabel("Quitar resaltado de la búsqueda")
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(theme.palette.surface, in: Capsule())
            .overlay(Capsule().stroke(theme.palette.border))
            .foregroundStyle(theme.palette.textSecondary)
            .padding(10)
        }
    }
}
