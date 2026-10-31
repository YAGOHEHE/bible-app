import BibliaCore
import SwiftUI

/// Panel «Notas» de la barra lateral: notas, resaltados y marcadores con filtros y búsqueda.
struct NotesPanel: View {
    @Environment(AppState.self) private var state
    @Environment(\.theme) private var theme
    @State private var pendingDelete: AnnotationItem?

    var body: some View {
        let m = state.annotationList
        @Bindable var mm = m
        VStack(spacing: 0) {
            controls(m, $mm.text)
            Divider().overlay(theme.palette.border)
            if m.items.isEmpty { emptyState(m) } else { list(m) }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .onAppear { m.refresh() }
        .onChange(of: state.annotationVersion) { _, _ in m.refresh() }
        .confirmationDialog("¿Eliminar esta nota?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                            titleVisibility: .visible, presenting: pendingDelete) { item in
            Button("Eliminar", role: .destructive) { m.delete(item) }
            Button("Cancelar", role: .cancel) {}
        } message: { item in Text(state.referenceLabel(for: item)) }
    }

    // MARK: filtros

    private func controls(_ m: AnnotationListModel, _ text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            FlowLayout(spacing: 6, lineSpacing: 6) {
                ForEach(AnnotationKindFilter.allCases) { k in
                    chip(k, m)
                }
            }
            if m.kind == .highlights {
                HStack(spacing: 8) {
                    Text("Color").font(theme.uiFont(size: 11)).foregroundStyle(theme.palette.textSecondary)
                    swatch(nil, m)
                    ForEach(HighlightColor.allCases) { swatch($0, m) }
                    Spacer(minLength: 0)
                }
            }
            HStack(spacing: 4) {
                Menu {
                    Picker("Libro", selection: Binding(get: { m.book ?? 0 }, set: { m.book = $0 == 0 ? nil : $0 })) {
                        Text("Todos los libros").tag(0)
                        Divider()
                        ForEach(state.bookNames, id: \.book) { Text($0.name).tag($0.book) }
                    }
                    .pickerStyle(.inline).labelsHidden()
                } label: {
                    Text("\(m.book.map { state.bookName($0) } ?? "Todos los libros") ▾").lineLimit(1)
                }
                .help("Filtrar por libro")
                .accessibilityLabel("Filtrar por libro")
                Text("·").foregroundStyle(theme.palette.textMuted)
                Menu {
                    Picker("Orden", selection: Binding(get: { m.sort }, set: { m.sort = $0 })) {
                        Text("Orden bíblico").tag(AnnotationSort.canonical)
                        Text("Recientes").tag(AnnotationSort.updated)
                    }
                    .pickerStyle(.inline).labelsHidden()
                } label: {
                    Text("\(m.sort == .canonical ? "Orden bíblico" : "Recientes") ▾").lineLimit(1)
                }
                .help("Ordenar")
                .accessibilityLabel("Orden de la lista")
                Spacer(minLength: 0)
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden)
            .font(theme.uiFont(size: 12))
            .foregroundStyle(theme.palette.textSecondary)
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(theme.palette.textMuted)
                TextField("Buscar en las notas", text: text)
                    .textFieldStyle(.plain)
                    .accessibilityLabel("Buscar en el texto de las notas")
                if !m.text.isEmpty {
                    Button { m.text = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(theme.palette.textMuted).accessibilityLabel("Borrar búsqueda")
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8).fill(theme.palette.surface))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(theme.palette.border, lineWidth: 1))
        }
        .padding(10)
    }

    private func chip(_ k: AnnotationKindFilter, _ m: AnnotationListModel) -> some View {
        let sel = m.kind == k
        return Button { m.kind = k } label: {
            Text("\(k.label) \(k.count(m.counts))")
                .font(theme.uiFont(size: 11, weight: sel ? .semibold : .regular)).lineLimit(1).monospacedDigit()
                .padding(.horizontal, 9).padding(.vertical, 3)
                .background(Capsule().fill(sel ? theme.palette.textPrimary : Color.clear))
                .overlay(Capsule().strokeBorder(sel ? Color.clear : theme.palette.border, lineWidth: 1))
                .foregroundStyle(sel ? theme.palette.background : theme.palette.textSecondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(k.label), \(k.count(m.counts))")
        .accessibilityAddTraits(sel ? .isSelected : [])
    }

    private func swatch(_ c: HighlightColor?, _ m: AnnotationListModel) -> some View {
        let sel = m.color == c
        return Button { m.color = c } label: {
            ZStack {
                Circle().fill(c.flatMap { theme.palette.highlight[$0] } ?? Color.clear)
                if c == nil { Image(systemName: "circle.slash").font(.system(size: 11)).foregroundStyle(theme.palette.textSecondary) }
            }
            .frame(width: 20, height: 20)
            .overlay(Circle().stroke(sel ? theme.palette.focusRing : theme.palette.borderInput, lineWidth: sel ? 2.5 : 1))
        }
        .buttonStyle(.plain)
        .help(c?.displayName ?? "Todos los colores")
        .accessibilityLabel(c?.displayName ?? "Todos los colores")
        .accessibilityAddTraits(sel ? .isSelected : [])
    }

    // MARK: lista

    private func list(_ m: AnnotationListModel) -> some View {
        List {
            ForEach(AnnotationGrouping.byChapter(m.items)) { group in
                Section {
                    ForEach(group.items) { item in
                        AnnotationRow(item: item)
                            .contentShape(Rectangle())
                            .onTapGesture { state.navigate(to: item) }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) { requestDelete(item, m) } label: { Label("Eliminar", systemImage: "trash") }
                            }
                            .contextMenu {
                                if item.kind == .highlight {
                                    Menu("Cambiar color") {
                                        ForEach(HighlightColor.allCases) { c in
                                            Button(c.displayName) { m.recolor(item, to: c) }.disabled(item.color == c)
                                        }
                                    }
                                }
                                Button("Ir al pasaje") { state.navigate(to: item) }
                                Button("Eliminar", role: .destructive) { requestDelete(item, m) }
                            }
                    }
                } header: {
                    Text("\(state.bookName(group.book)) \(group.chapter)".uppercased())
                        .font(theme.uiFont(size: 11, weight: .semibold)).tracking(0.8)
                        .foregroundStyle(theme.palette.textMuted)
                        .accessibilityLabel("\(state.bookName(group.book)) \(group.chapter)")
                        .accessibilityAddTraits(.isHeader)
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
    }

    private func requestDelete(_ item: AnnotationItem, _ m: AnnotationListModel) {
        if item.kind == .note { pendingDelete = item } else { m.delete(item) }
    }

    private func emptyState(_ m: AnnotationListModel) -> some View {
        let title: String, desc: String, symbol: String
        let searching = !m.text.trimmingCharacters(in: .whitespaces).isEmpty
        if searching {
            (title, desc, symbol) = ("Sin resultados", "Ninguna nota contiene «\(m.text.trimmingCharacters(in: .whitespaces))».", "magnifyingglass")
        } else if m.book != nil || m.color != nil {
            (title, desc, symbol) = ("Nada con estos filtros", "Prueba con otro libro o color.", "line.3.horizontal.decrease")
        } else {
            switch m.kind {
            case .all: (title, desc, symbol) = ("Aún no hay anotaciones", "Selecciona un versículo para resaltarlo, anotarlo o marcarlo.", "square.and.pencil")
            case .notes: (title, desc, symbol) = ("Sin notas", "Selecciona un versículo y pulsa Anotar (⌥⌘N).", "square.and.pencil")
            case .highlights: (title, desc, symbol) = ("Sin resaltados", "Selecciona un versículo y elige un color.", "highlighter")
            case .bookmarks: (title, desc, symbol) = ("Sin marcadores", "Selecciona un versículo y pulsa Marcador (⌘D).", "bookmark")
            }
        }
        return VStack(spacing: 8) {
            ContentUnavailableView(title, systemImage: symbol, description: Text(desc))
            if m.isFiltered { Button("Quitar filtros") { m.clearFilters() } }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct AnnotationRow: View {
    @Environment(AppState.self) private var state
    @Environment(\.theme) private var theme
    let item: AnnotationItem
    @State private var verse: String?

    var body: some View {
        let ref = state.referenceLabel(for: item)
        let date = DateText.date(item.updatedAt)
        let title = item.kind == .note ? (item.noteId.flatMap { _ in Self.title(item.body ?? "") }) : nil
        HStack(alignment: .top, spacing: 8) {
            icon.frame(width: 18, height: 18).padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(ref).font(.callout.weight(.semibold)).foregroundStyle(theme.palette.textPrimary)
                    Spacer(minLength: 4)
                    Text(date).font(.caption2).foregroundStyle(theme.palette.textMuted)
                }
                if let title, !title.isEmpty {
                    Text(title).font(.callout).lineLimit(1).foregroundStyle(theme.palette.textPrimary)
                }
                Text(verse ?? "—").font(.caption).lineLimit(2)
                    .foregroundStyle(theme.palette.textSecondary)
            }
        }
        .padding(.vertical, 2)
        .task(id: "\(item.id)-\(state.translationId)") {
            verse = state.passageText(book: item.book, chapter: item.chapter, from: item.verseStart, to: max(item.verseStart, item.verseEnd))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(kindName), \(ref)\(title.map { ". " + $0 } ?? "")")
    }

    private var kindName: String {
        switch item.kind { case .note: "Nota"; case .bookmark: "Marcador"; case .highlight: "Resaltado \(item.color?.displayName ?? "")" }
    }

    @ViewBuilder private var icon: some View {
        switch item.kind {
        case .note: Image(systemName: "square.and.pencil").foregroundStyle(theme.palette.accent)
        case .bookmark: Image(systemName: "bookmark.fill").foregroundStyle(theme.palette.bookmarkMarker)
        case .highlight:
            Circle().fill(item.color.flatMap { theme.palette.highlight[$0] } ?? Color.clear)
                .overlay(Circle().stroke(theme.palette.borderInput, lineWidth: 1)).frame(width: 14, height: 14)
        }
    }

    /// Título de la nota sin marcas de Markdown (**, *, `, #, >, -).
    static func title(_ body: String) -> String {
        let t = Note(id: 0, book: 0, chapter: 0, verseStart: 0, verseEnd: 0, body: body, createdAt: 0, updatedAt: 0).title
        let cleaned = t.replacingOccurrences(of: "[*_`]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "^\\s*([#>\\-]+\\s*)+", with: "", options: .regularExpression)
        return cleaned.trimmingCharacters(in: .whitespaces)
    }
}
