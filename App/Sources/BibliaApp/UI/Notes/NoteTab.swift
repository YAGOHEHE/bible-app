import BibliaCore
import SwiftUI

/// Pestaña «Nota» del inspector: referencia + texto, notas del rango y editor Markdown con vista previa.
struct NoteTab: View {
    @Environment(AppState.self) private var state
    @Environment(\.theme) private var theme
    @FocusState private var editorFocused: Bool
    @State private var confirmDelete = false

    var body: some View {
        let m = state.noteEditor
        Group {
            if !m.hasTarget && state.noteRequest.token == 0 {
                empty
            } else {
                content(m)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { if state.noteRequest.token > 0 { m.load(state.noteRequest) } }
        .onChange(of: state.noteRequest) { _, r in m.load(r) }
        .onChange(of: m.focusToken) { _, _ in if !m.preview { editorFocused = true } }
        .onDisappear { m.flush() }
        .confirmationDialog("¿Eliminar esta nota?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Eliminar", role: .destructive) { m.deleteSelected() }
            Button("Cancelar", role: .cancel) {}
        } message: { Text("Esta acción no se puede deshacer.") }
    }

    private var empty: some View {
        VStack(spacing: 10) {
            Image(systemName: "square.and.pencil").font(.system(size: 28)).foregroundStyle(theme.palette.textMuted)
            Text("Notas").font(.headline).foregroundStyle(theme.palette.textPrimary)
            Text("Selecciona un versículo y pulsa Anotar (⌥⌘N).")
                .font(.callout).foregroundStyle(theme.palette.textSecondary).multilineTextAlignment(.center)
            if state.isEnabled(.note) {
                Button("Anotar la selección") { state.perform(.note) }
            }
        }
        .padding(24).frame(maxHeight: .infinity)
        .accessibilityElement(children: .contain)
    }

    private func date(_ t: Double) -> String {
        DateText.dateTime(t)
    }

    @ViewBuilder private func content(_ m: NoteEditorModel) -> some View {
        @Bindable var mm = m
        let r = m.editingRange
        let label = RefLabel.text(bookName: state.bookName(m.book), chapter: m.chapter, from: r.lowerBound, to: r.upperBound)
        let text = state.passageText(book: m.book, chapter: m.chapter, from: r.lowerBound, to: r.upperBound)
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(label).font(.headline).foregroundStyle(theme.palette.heading)
                Text(text ?? "Este versículo no existe en \(state.translationId).")
                    .font(theme.readingFont(latin: state.isLatin, size: 14))
                    .foregroundStyle(text == nil ? theme.palette.textMuted : theme.palette.textSecondary)
                    .lineLimit(4)
            }
            .accessibilityElement(children: .combine)

            if m.notes.count > 1 || (m.notes.count == 1 && m.selectedId == nil) { noteList(m) }

            Picker("Modo", selection: $mm.preview) {
                Text("Editar").tag(false)
                Text("Vista previa").tag(true)
            }
            .pickerStyle(.segmented).labelsHidden()
            .accessibilityLabel("Editar o ver vista previa")

            if m.preview {
                ScrollView {
                    Group {
                        if m.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text("Nada que mostrar.").foregroundStyle(theme.palette.textMuted)
                        } else {
                            Text(MarkdownPreview.render(m.draft)).foregroundStyle(theme.palette.textPrimary)
                        }
                    }
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(8)
                    .textSelection(.enabled)
                }
                .frame(minHeight: 120, maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: 6).fill(theme.palette.background))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(theme.palette.border))
                .accessibilityLabel("Vista previa de la nota")
            } else {
                TextEditor(text: $mm.draft)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .foregroundStyle(theme.palette.textPrimary)
                    .focused($editorFocused)
                    .padding(4)
                    .frame(minHeight: 120, maxHeight: .infinity)
                    .background(RoundedRectangle(cornerRadius: 6).fill(theme.palette.background))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(editorFocused ? theme.palette.focusRing : theme.palette.borderInput,
                                                                       lineWidth: editorFocused ? 2 : 1))
                    .help("Markdown: **negrita**, *cursiva*, `código`, [enlace](https://…)")
                    .accessibilityLabel("Texto de la nota, Markdown")
            }

            if let err = m.errorMessage {
                Text(err).font(.caption).foregroundStyle(theme.palette.danger)
            }
            VStack(alignment: .leading, spacing: 1) {
                if let c = m.createdAt { Text("Creada: \(date(c))") }
                if let u = m.updatedAt, u != m.createdAt { Text("Modificada: \(date(u))") }
                Text(m.isDirty ? "Guardando…" : (m.selectedId == nil ? "Sin guardar" : "Guardada"))
            }
            .font(.caption).foregroundStyle(theme.palette.textMuted)
            HStack {
                Button { m.newNote() } label: { Label("Nueva nota", systemImage: "plus") }
                    .help("Añadir otra nota a este versículo")
                    .disabled(m.selectedId == nil && m.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Spacer()
                Button(role: .destructive) { confirmDelete = true } label: { Label("Eliminar", systemImage: "trash") }
                    .disabled(m.selectedId == nil)
            }
        }
        .padding([.horizontal, .bottom], 12)
    }

    private func noteList(_ m: NoteEditorModel) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Notas en este pasaje (\(m.notes.count))").font(.caption.weight(.semibold))
                .foregroundStyle(theme.palette.textSecondary)
            ForEach(m.notes) { n in
                let sel = n.id == m.selectedId
                Button { m.select(n.id) } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.pencil").foregroundStyle(theme.palette.accent)
                        Text(n.title).lineLimit(1).foregroundStyle(theme.palette.textPrimary)
                        Spacer(minLength: 4)
                        Text(n.verseStart == n.verseEnd ? "\(n.verseStart)" : "\(n.verseStart)–\(n.verseEnd)")
                            .font(.caption.monospacedDigit()).foregroundStyle(theme.palette.textMuted)
                    }
                    .padding(.horizontal, 6).padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 5).fill(sel ? theme.palette.selection : Color.clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Nota: \(n.title)\(sel ? ", seleccionada" : "")")
            }
        }
    }
}
