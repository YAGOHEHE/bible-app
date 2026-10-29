import SwiftUI

/// S07: historial de lectura (hoja, ⌘Y).
struct HistoryView: View {
    @Environment(AppState.self) private var state
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var days: [HistoryDay] = []
    @State private var confirmClear = false

    private func time(_ e: HistoryEntry) -> String {
        DateText.time(e.at)
    }
    private func reference(_ e: HistoryEntry) -> String {
        let lang = state.translations.first { $0.id == e.translationId }?.language ?? state.language
        let name = state.bookName(e.book, language: lang)
        let sep = lang == "zh" ? "" : " "
        return "\(name)\(sep)\(e.chapter)" + (e.verse.map { ":\($0)" } ?? "")
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Historial").font(.headline)
                Spacer()
                Button("Borrar historial", role: .destructive) { confirmClear = true }.disabled(days.isEmpty)
                Button("Cerrar") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(12)
            Divider()
            if days.isEmpty {
                ContentUnavailableView("Sin historial", systemImage: "clock",
                                       description: Text("Los capítulos que leas aparecerán aquí."))
                    .foregroundStyle(theme.palette.textSecondary)
            } else {
                List {
                    ForEach(days) { day in
                        Section(day.title) {
                            ForEach(day.entries) { e in
                                Button { state.openHistory(e) } label: {
                                    HStack {
                                        Text(reference(e)).font(.system(size: 13, weight: .semibold))
                                            .foregroundStyle(theme.palette.textPrimary)
                                        Text(e.translationId).font(.system(size: 11, weight: .medium))
                                            .padding(.horizontal, 6).padding(.vertical, 1)
                                            .background(theme.palette.surface, in: Capsule())
                                            .foregroundStyle(theme.palette.textSecondary)
                                        Spacer()
                                        Text(e.kind == "page" ? "Pasar página" : "Salto").font(.system(size: 11))
                                            .foregroundStyle(theme.palette.textMuted)
                                        Text(time(e)).font(.system(size: 11)).monospacedDigit()
                                            .foregroundStyle(theme.palette.textMuted)
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("\(reference(e)), \(e.translationId), \(e.kind == "page" ? "pasar página" : "salto"), \(time(e))")
                            }
                        }
                    }
                }
            }
        }
        .frame(width: 520, height: 520)
        .background(theme.palette.background)
        .onAppear { days = state.historyDays() }
        .confirmationDialog("¿Borrar todo el historial?", isPresented: $confirmClear) {
            Button("Borrar historial", role: .destructive) { state.clearHistory(); days = [] }
            Button("Cancelar", role: .cancel) {}
        } message: { Text("Esta acción no se puede deshacer.") }
    }
}
