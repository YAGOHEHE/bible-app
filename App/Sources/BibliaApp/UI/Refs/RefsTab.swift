import BibliaCore
import SwiftUI

/// Pestaña «Referencias» del inspector: referencias cruzadas del rango, de más a menos votadas.
struct RefsTab: View {
    @Environment(AppState.self) private var state
    @Environment(\.theme) private var theme
    @State private var all: [CrossRef] = []
    @State private var shown = CrossRefList.pageSize
    @State private var loaded = false

    private struct Key: Equatable { var r: ClosedRange<Int>?; var b: Int; var c: Int; var t: String }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let r = state.refsTarget, state.refsBook > 0 {
                header(r)
                Divider().overlay(theme.palette.border)
                if !loaded {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if all.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "arrow.triangle.branch").font(.system(size: 28)).foregroundStyle(theme.palette.textMuted)
                        Text("Sin referencias cruzadas").font(.headline).foregroundStyle(theme.palette.textPrimary)
                        Text("Este pasaje no tiene referencias en el conjunto de datos.")
                            .font(.callout).foregroundStyle(theme.palette.textSecondary).multilineTextAlignment(.center)
                    }
                    .padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    list
                }
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "arrow.triangle.branch").font(.system(size: 28)).foregroundStyle(theme.palette.textMuted)
                    Text("Referencias").font(.headline).foregroundStyle(theme.palette.textPrimary)
                    Text("Selecciona un versículo y elige Referencias en la barra de acciones.")
                        .font(.callout).foregroundStyle(theme.palette.textSecondary).multilineTextAlignment(.center)
                }
                .padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: Key(r: state.refsTarget, b: state.refsBook, c: state.refsChapter, t: state.translationId)) {
            loaded = false
            all = state.crossRefs()
            shown = CrossRefList.pageSize
            loaded = true
        }
    }

    private func header(_ r: ClosedRange<Int>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(RefLabel.text(bookName: state.bookName(state.refsBook), chapter: state.refsChapter,
                               from: r.lowerBound, to: r.upperBound))
                .font(.headline).foregroundStyle(theme.palette.heading)
            Text(loaded ? (all.count == 1 ? "1 referencia" : "\(all.count) referencias") + " · de más a menos votadas" : "Cargando…")
                .font(.caption).foregroundStyle(theme.palette.textMuted)
        }
        .padding(.horizontal, 12).padding(.bottom, 8)
        .accessibilityElement(children: .combine)
    }

    private var list: some View {
        List {
            ForEach(all.prefix(shown), id: \.self) { r in
                let row = state.crossRefRow(r)
                Button { state.navigate(to: row.target) } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(row.label).font(.callout.weight(.semibold)).foregroundStyle(theme.palette.accent)
                            Spacer(minLength: 4)
                            Text("\(row.votes)").font(.caption2.monospacedDigit()).foregroundStyle(theme.palette.textMuted)
                                .help("Votos")
                        }
                        Text(row.snippet ?? "—")
                            .font(.callout).lineLimit(3)
                            .foregroundStyle(row.snippet == nil ? theme.palette.textMuted : theme.palette.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(row.label). \(row.snippet ?? "Este versículo no existe en esta versión.")")
                .accessibilityHint("Ir al pasaje")
            }
            if all.count > shown {
                Button("Mostrar más (\(all.count - shown) restantes)") { shown += CrossRefList.pageSize }
                    .buttonStyle(.link)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }
}
