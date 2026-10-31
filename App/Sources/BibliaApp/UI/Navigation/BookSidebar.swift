import BibliaCore
import SwiftUI

/// S02: recientes (cápsulas), libros AT/NT plegables y cuadrícula de capítulos bajo el libro elegido.
struct BookSidebar: View {
    @Environment(AppState.self) private var state
    @Environment(\.theme) private var theme
    @State private var filter = ""
    @State private var otOpen = true
    @State private var ntOpen = true
    @FocusState private var filterFocused: Bool

    private func matches(_ b: BookName) -> Bool {
        let q = filter.trimmingCharacters(in: .whitespaces)
        if q.isEmpty { return true }
        let opts: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        return b.name.range(of: q, options: opts) != nil || (b.abbrev?.range(of: q, options: opts) != nil)
    }

    private var sections: [TestamentSection] { TestamentSplit.sections(state.bookNames.filter(matches)) }

    var body: some View {
        let filtering = !filter.trimmingCharacters(in: .whitespaces).isEmpty
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(theme.palette.textMuted)
                TextField("Filtrar libros", text: $filter)
                    .textFieldStyle(.plain)
                    .focused($filterFocused)
                    .onSubmit {
                        if let first = sections.first?.books.first { state.jump(book: first.book); filter = "" }
                    }
                    .accessibilityLabel("Filtrar libros por nombre")
                if !filter.isEmpty {
                    Button { filter = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(theme.palette.textMuted)
                        .accessibilityLabel("Borrar filtro")
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8).fill(theme.palette.surface))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(theme.palette.border, lineWidth: 1))
            .padding(.horizontal, 10).padding(.top, 8).padding(.bottom, 6)

            if !filtering, !state.recentBooks.isEmpty { RecentChipsRow() }

            ScrollViewReader { proxy in
                // Una fila por libro (con su cuadrícula dentro si es el elegido) y sin selección del
                // sistema: la List de macOS no recolocaba una fila insertada y la cuadrícula se quedaba
                // bajo Génesis. Así el número de filas nunca cambia; solo su contenido.
                List {
                    ForEach(sections, id: \.title) { sec in
                        let open = filtering || (sec.title.hasPrefix("Antiguo") ? otOpen : ntOpen)
                        Section(isExpanded: Binding(
                            get: { open },
                            set: { v in if !filtering { if sec.title.hasPrefix("Antiguo") { otOpen = v } else { ntOpen = v } } })) {
                            ForEach(sec.books, id: \.book) { b in
                                BookRow(book: b).id("book-\(b.book)")
                            }
                        } header: {
                            HStack(spacing: 6) {
                                Text(sec.title).font(theme.uiFont(size: 11, weight: .semibold))
                                    .textCase(.uppercase).tracking(0.8)
                                Text("\(sec.count)").font(theme.uiFont(size: 11)).monospacedDigit()
                                    .foregroundStyle(theme.palette.textMuted)
                                    .accessibilityLabel("\(sec.count) libros")
                            }
                            .foregroundStyle(theme.palette.textMuted)
                        }
                    }
                    if sections.isEmpty {
                        Text("Ningún libro coincide con «\(filter)»").foregroundStyle(theme.palette.textMuted)
                    }
                }
                .listStyle(.sidebar)
                .tint(theme.palette.accent)
                .scrollContentBackground(.hidden)
                .onAppear { scrollToCurrent(proxy) }
                .onChange(of: state.book) { _, _ in scrollToCurrent(proxy) }
            }
        }
    }

    private func scrollToCurrent(_ proxy: ScrollViewProxy) {
        DispatchQueue.main.async { withAnimation(.none) { proxy.scrollTo("book-\(state.book)", anchor: .center) } }
    }
}

/// Recientes: cápsulas pequeñas en una sola fila (desplazable si no caben).
private struct RecentChipsRow: View {
    @Environment(AppState.self) private var state
    @Environment(\.theme) private var theme

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Image(systemName: "clock").font(.system(size: 11)).foregroundStyle(theme.palette.textMuted)
                    .accessibilityHidden(true)
                ForEach(RecentChips.books(state.recentBooks), id: \.self) { n in
                    let current = n == state.book
                    Button { state.jump(book: n) } label: {
                        Text(state.bookName(n)).font(theme.uiFont(size: 11, weight: current ? .semibold : .regular))
                            .lineLimit(1)
                            .padding(.horizontal, 9).padding(.vertical, 3)
                            .foregroundStyle(current ? theme.palette.accent : theme.palette.textSecondary)
                            .background(Capsule().fill(current ? theme.palette.accent.opacity(0.12) : Color.clear))
                            .overlay(Capsule().strokeBorder(current ? Color.clear : theme.palette.border, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .help("Ir a \(state.bookName(n)) (reciente)")
                    .accessibilityLabel("Reciente: \(state.bookName(n))")
                }
            }
            .padding(.horizontal, 12)
        }
        .padding(.bottom, 6)
    }
}

/// Fila de un libro: el nombre (pulsable) y, si es el libro actual, su cuadrícula de capítulos debajo.
private struct BookRow: View {
    @Environment(AppState.self) private var state
    @Environment(\.theme) private var theme
    let book: BookName

    var body: some View {
        let current = book.book == state.book
        VStack(alignment: .leading, spacing: 4) {
            Button { if !current { state.jump(book: book.book) } } label: {
                Text(book.name)
                    .font(theme.uiFont(size: 13, weight: current ? .semibold : .regular))
                    .foregroundStyle(current ? theme.palette.accent : theme.palette.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 6)
                        .fill(current ? theme.palette.accent.opacity(0.12) : Color.clear))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(book.name), libro \(book.book) de 66")
            .accessibilityAddTraits(current ? .isSelected : [])
            if current { ChapterGrid() }
        }
        .listRowInsets(EdgeInsets(top: 1, leading: 4, bottom: 1, trailing: 8))
    }
}

/// Cuadrícula de capítulos del libro elegido: 7 columnas, celdas de 30 pt, capítulo actual con fondo acento.
private struct ChapterGrid: View {
    @Environment(AppState.self) private var state
    @Environment(\.theme) private var theme

    var body: some View {
        let count = state.chapterCounts[safe: state.book - 1] ?? 0
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 22, maximum: 30), spacing: 4), count: 7),
                  spacing: 4) {
            ForEach(1...max(1, count), id: \.self) { c in
                let sel = c == state.chapter
                Button { state.jump(book: state.book, chapter: c) } label: {
                    Text("\(c)").monospacedDigit()
                        .font(theme.uiFont(size: 12, weight: sel ? .semibold : .regular))
                        .frame(maxWidth: .infinity, minHeight: 30, maxHeight: 30)
                        .background(RoundedRectangle(cornerRadius: 6)
                            .fill(sel ? theme.palette.accent : theme.palette.surface))
                        .foregroundStyle(sel ? theme.palette.onAccent : theme.palette.textPrimary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Capítulo \(c)")
                .accessibilityAddTraits(sel ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
        .listRowSeparator(.hidden)
    }
}
