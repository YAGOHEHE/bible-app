import BibliaCore
import SwiftUI

/// S04: gestor de versiones (hoja ⌥⌘V). Lista con orden por arrastre, activar para la vista paralela y principal.
struct VersionManagerView: View {
    @Environment(AppState.self) private var state
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Versiones").font(.title2.bold())
                Spacer()
                Button("Importar módulo…") {}.disabled(true).help("Próximamente")
                Button("Listo") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            Text("Activa 2 o 3 versiones para la vista paralela (⌘\\), arrástralas para ordenarlas y elige la principal (estrella). La principal es la del lector y va siempre en la primera columna.")
                .font(.callout).foregroundStyle(.secondary)
            VersionEmptyNote()
            List {
                ForEach(orderedTranslations) { t in
                    VersionRow(t: t, showMoveButtons: true)
                }
                .onMove { state.moveVersions(from: $0, to: $1) }
            }
            .listStyle(.inset)
            .frame(minHeight: 200)
            GlossSection()
        }
        .padding(20)
        .frame(width: 600, height: 620)
        .background(theme.palette.background)
    }

    private var orderedTranslations: [Translation] {
        state.versionSet.order.compactMap { id in state.translations.first { $0.id == id } }
    }
}

struct VersionEmptyNote: View {
    @Environment(AppState.self) private var state
    @Environment(\.theme) private var theme

    var body: some View {
        if state.activeVersionCount < 2 {
            Label("Solo hay una versión activa. Marca la casilla de otra versión para poder compararlas en paralelo.",
                  systemImage: "info.circle")
                .font(.callout)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.palette.surface, in: RoundedRectangle(cornerRadius: 8))
                .foregroundStyle(theme.palette.textPrimary)
        } else if state.activeVersionCount > VersionSet.maxColumns {
            Label("Hay más de 3 versiones activas: la vista paralela muestra la principal y las dos primeras del orden.",
                  systemImage: "info.circle")
                .font(.callout)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.palette.surface, in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

struct VersionRow: View {
    @Environment(AppState.self) private var state
    @Environment(\.theme) private var theme
    let t: Translation
    var showMoveButtons: Bool

    private var isPrimary: Bool { t.id == state.translationId }
    private var enabled: Bool { isPrimary || state.versionSet.enabled.contains(t.id) }
    private var index: Int { state.versionSet.order.firstIndex(of: t.id) ?? 0 }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Toggle("Activar \(t.id)", isOn: Binding(get: { enabled }, set: { state.setVersionEnabled(t.id, $0) }))
                .labelsHidden()
                .disabled(isPrimary)
                .help(isPrimary ? "La versión principal siempre está activa" : "Incluir en la vista paralela")
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(t.name).font(.headline).lineLimit(2)
                    Text(t.id).font(.caption.monospaced()).foregroundStyle(.secondary)
                }
                HStack(spacing: 6) {
                    pill(languageName(t.language), filled: false)
                    if t.hasStrongs { pill("tiene Strong", filled: true) }
                    if isPrimary { pill("Principal", filled: true) }
                }
                Text("Licencia: \(t.license ?? "no indicada")").font(.caption).foregroundStyle(.secondary)
                if let u = t.sourceURL {
                    Text("Fuente: \(u)").font(.caption).foregroundStyle(.secondary)
                        .textSelection(.enabled).lineLimit(1).truncationMode(.middle)
                }
            }
            Spacer(minLength: 0)
            Button { state.setPrimary(t.id) } label: { Image(systemName: isPrimary ? "star.fill" : "star") }
                .buttonStyle(.borderless)
                .help(isPrimary ? "Versión principal" : "Establecer como principal")
                .accessibilityLabel(isPrimary ? "Versión principal" : "Establecer \(t.id) como principal")
            if showMoveButtons {
                Button { state.moveVersion(t.id, by: -1) } label: { Image(systemName: "chevron.up") }
                    .buttonStyle(.borderless).disabled(index == 0).help("Subir")
                    .accessibilityLabel("Subir \(t.id)")
                Button { state.moveVersion(t.id, by: 1) } label: { Image(systemName: "chevron.down") }
                    .buttonStyle(.borderless).disabled(index >= state.versionSet.order.count - 1).help("Bajar")
                    .accessibilityLabel("Bajar \(t.id)")
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private func pill(_ s: String, filled: Bool) -> some View {
        Text(s).font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 7).padding(.vertical, 1)
            .foregroundStyle(filled ? theme.palette.onAccent : theme.palette.textSecondary)
            .background(filled ? theme.palette.accent : theme.palette.surface, in: Capsule())
            .overlay(Capsule().stroke(filled ? Color.clear : theme.palette.border))
    }
}

/// Glosas del modo intercalado: por idioma, máx. 3, sin la principal (se guardan aparte de las columnas).
struct GlossSection: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Glosas del modo intercalado").font(.headline)
            Text("Versiones que aparecen en letra pequeña bajo cada versículo de la principal (máx. \(GlossSet.maxGlosses)).")
                .font(.callout).foregroundStyle(.secondary)
            ForEach(GlossSet.grouped(state.translations, primary: state.translationId), id: \.language) { group in
                HStack(spacing: 10) {
                    Text(languageName(group.language)).font(.callout).foregroundStyle(.secondary)
                        .frame(width: 64, alignment: .leading)
                    ForEach(group.items) { t in
                        Toggle(t.id, isOn: Binding(get: { state.glossSet.contains(t.id) }, set: { _ in state.toggleGloss(t.id) }))
                            .toggleStyle(.checkbox)
                            .disabled(!state.glossSet.canAdd(t.id, primary: state.translationId))
                            .help(t.name)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }
}
