import SwiftUI

/// S02: libros AT/NT (idioma de la versión), recientes, filtro y cuadrícula de capítulos.
struct BookSidebar: View {
    @Environment(AppState.self) private var state
    @Environment(\.theme) private var theme
    @State private var filter = ""
    @FocusState private var filterFocused: Bool

    private func matches(_ b: BookName) -> Bool {
        let q = filter.trimmingCharacters(in: .whitespaces)
        if q.isEmpty { return true }
        let opts: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        return b.name.range(of: q, options: opts) != nil || (b.abbrev?.range(of: q, options: opts) != nil)
    }

    private var ot: [BookName] { state.bookNames.filter { $0.book <= 39 && matches($0) } }
    private var nt: [BookName] { state.bookNames.filter { $0.book >= 40 && matches($0) } }

    var body: some View {
        let selection = Binding<String?>(
            get: { "b\(state.book)" },
            set: { if let s = $0, let n = Int(s.dropFirst()), n != state.book || s.hasPrefix("r") { state.jump(book: n) } })
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Filtrar libros", text: $filter)
                    .textFieldStyle(.plain)
                    .focused($filterFocused)
                    .onSubmit {
                        if let first = (ot + nt).first { state.jump(book: first.book); filter = "" }
                    }
                    .accessibilityLabel("Filtrar libros por nombre")
                if !filter.isEmpty {
                    Button { filter = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                        .accessibilityLabel("Borrar filtro")
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary.opacity(0.5)))
            .padding(.horizontal, 10).padding(.top, 8).padding(.bottom, 6)

            List(selection: selection) {
                if filter.isEmpty, !state.recentBooks.isEmpty {
                    Section("Recientes") {
                        ForEach(state.recentBooks, id: \.self) { n in
                            Label(state.bookName(n), systemImage: "clock").tag("r\(n)")
                        }
                    }
                }
                if !ot.isEmpty {
                    Section("Antiguo Testamento") {
                        ForEach(ot, id: \.book) { b in row(b) }
                    }
                }
                if !nt.isEmpty {
                    Section("Nuevo Testamento") {
                        ForEach(nt, id: \.book) { b in row(b) }
                    }
                }
                if ot.isEmpty && nt.isEmpty {
                    Text("Ningún libro coincide con «\(filter)»").foregroundStyle(.secondary)
                }
            }
            .listStyle(.sidebar)

            Divider()
            ChapterGrid()
        }
    }

    private func row(_ b: BookName) -> some View {
        Text(b.name).tag("b\(b.book)")
            .accessibilityLabel("\(b.name), libro \(b.book) de 66")
    }
}

private struct ChapterGrid: View {
    @Environment(AppState.self) private var state
    @Environment(\.theme) private var theme

    var body: some View {
        let count = state.chapterCounts[safe: state.book - 1] ?? 0
        VStack(alignment: .leading, spacing: 6) {
            Text("\(state.bookName(state.book)) · \(count) cap.")
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 34), spacing: 4)], spacing: 4) {
                    ForEach(1...max(1, count), id: \.self) { c in
                        let sel = c == state.chapter
                        Button { state.jump(book: state.book, chapter: c) } label: {
                            Text("\(c)").monospacedDigit().font(.system(size: 12, weight: sel ? .semibold : .regular))
                                .frame(maxWidth: .infinity, minHeight: 26)
                                .background(RoundedRectangle(cornerRadius: 6)
                                    .fill(sel ? theme.palette.accent : Color.secondary.opacity(0.12)))
                                .foregroundStyle(sel ? theme.palette.onAccent : Color.primary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Capítulo \(c)")
                    }
                }
            }
            .frame(maxHeight: 170)
        }
        .padding(10)
    }
}
