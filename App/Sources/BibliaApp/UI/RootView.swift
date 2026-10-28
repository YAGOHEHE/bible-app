import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        switch state.load {
        case .loading:
            ProgressView().frame(minWidth: 600, minHeight: 400)
        case .missingData:
            ContentUnavailableView("Datos no encontrados", systemImage: "books.vertical",
                                   description: Text("No se encontró bible.sqlite dentro de la aplicación."))
                .frame(minWidth: 600, minHeight: 400)
        case .failed(let msg):
            ContentUnavailableView("Error al abrir los datos", systemImage: "exclamationmark.triangle",
                                   description: Text(msg)).frame(minWidth: 600, minHeight: 400)
        case .ready:
            NavigationSplitView {
                BookSidebar()
            } detail: {
                ReaderView()
            }
            .frame(minWidth: 800, minHeight: 500)
        }
    }
}

/// S02 (placeholder): lista de libros desde la BD.
struct BookSidebar: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var s = state
        List(selection: $s.selectedBook) {
            ForEach(state.bookNames, id: \.book) { b in
                Text(b.name).tag(b.book)
            }
        }
        .navigationSplitViewColumnWidth(min: 160, ideal: 200)
        .onChange(of: state.selectedBook) { _, new in if let new { state.select(book: new) } }
    }
}

/// S01 (mínimo): versículos como Text plano. S03/S05/S06/S07 son stubs.
struct ReaderView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                Text("\(state.selectedBook.map(state.bookName) ?? "") \(state.chapter)").font(.title)
                if state.verses.isEmpty {
                    Text("Sin versículos para este capítulo.").foregroundStyle(.secondary)
                }
                ForEach(state.verses) { v in
                    if let h = state.headings.first(where: { $0.verse == v.verse }) {
                        Text(h.text).font(.headline).padding(.top, 8)
                    }
                    Text("\(v.verse) \(v.text)").textSelection(.enabled)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct ParallelView: View { var body: some View { Text("Paralelo (S03)") } }
struct SearchResultsView: View { var body: some View { Text("Búsqueda (S05)") } }
struct StrongPanel: View { var body: some View { Text("Strong (S06)") } }
struct HistoryView: View { var body: some View { Text("Historial (S07)") } }
struct SettingsView: View { var body: some View { Text("Ajustes (S08)").padding(40) } }
