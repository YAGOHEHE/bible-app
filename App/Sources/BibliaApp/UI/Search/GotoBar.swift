import BibliaCore
import SwiftUI

/// Barra "Ir a referencia" (⌘L): flotante sobre el lector. Acepta zh/es/en, rangos y solo capítulo.
struct GotoBar: View {
    @Environment(AppState.self) private var state
    @Environment(SearchModel.self) private var search
    @Environment(\.theme) private var theme
    @State private var text = ""
    @State private var error: String?
    @State private var offerSearch = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.turn.down.right").foregroundStyle(theme.palette.textSecondary)
                TextField("Ir a referencia: Juan 3:16, 约3:16, Rom 8:28-39", text: $text)
                    .textFieldStyle(.plain).font(.system(size: 15))
                    .focused($focused)
                    .onSubmit(go)
                    .onKeyPress(.escape) { close(); return .handled }
                    .onChange(of: text) { _, _ in error = nil; offerSearch = false }
                    .accessibilityLabel("Ir a referencia")
                Button("Ir", action: go).disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if let error {
                Text(error).font(.callout).foregroundStyle(theme.palette.danger)
                    .accessibilityLabel("Error: \(error)")
                if offerSearch {
                    Button("Buscar «\(text.trimmingCharacters(in: .whitespaces))»") {
                        let q = text.trimmingCharacters(in: .whitespaces)
                        close(); search.start(q)
                    }
                    .buttonStyle(.link)
                }
            }
        }
        .padding(12)
        .frame(width: 460)
        .background(theme.palette.surface, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(theme.palette.border))
        .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
        .padding(.top, 10)
        .onAppear { focused = true }
    }

    private func go() {
        let input = text
        guard !input.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        switch state.goTo(input) {
        case .went: close()
        case .failed(let f):
            error = state.gotoMessage(f, input: input)
            offerSearch = (f == .notReference)
        }
    }

    private func close() { state.showGoto = false }
}
