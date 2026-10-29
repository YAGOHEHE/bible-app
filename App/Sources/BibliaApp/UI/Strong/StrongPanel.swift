import SwiftUI

/// S06: inspector Strong (léxico + otras apariciones).
struct StrongPanel: View {
    @Environment(AppState.self) private var state
    @Environment(\.theme) private var theme

    var body: some View {
        Group {
            if state.strongLoading {
                VStack(spacing: 8) { ProgressView(); Text("Cargando…").font(.callout).foregroundStyle(theme.palette.textSecondary) }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let id = state.strongId {
                if let e = state.strongEntry { entry(e) } else { missing(id) }
            } else if state.strongSelection != nil || state.strongWord != nil {
                placeholder("Esta palabra no tiene número Strong", "Solo las palabras subrayadas llevan número.")
            } else {
                emptyState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(theme.palette.surface)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Inspector Strong")
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "textformat.abc.dottedunderline").font(.system(size: 28)).foregroundStyle(theme.palette.textMuted)
            Text("Activa el modo Strong y toca una palabra").font(.headline).multilineTextAlignment(.center)
                .foregroundStyle(theme.palette.textPrimary)
            if !state.strongAvailable {
                Text("Esta versión no tiene números Strong. Cambia a KJV.").font(.callout)
                    .foregroundStyle(theme.palette.textSecondary).multilineTextAlignment(.center)
            } else if !state.strongMode {
                Button("Activar modo Strong") { state.setStrongMode(true) }
            }
        }
        .padding(24).frame(maxHeight: .infinity)
    }

    private func placeholder(_ t: String, _ d: String) -> some View {
        VStack(spacing: 8) {
            Text(t).font(.headline).foregroundStyle(theme.palette.textPrimary)
            Text(d).font(.callout).foregroundStyle(theme.palette.textSecondary).multilineTextAlignment(.center)
        }.padding(24).frame(maxHeight: .infinity)
    }

    private func missing(_ id: String) -> some View {
        placeholder("\(id): sin definición", "Este número no tiene definición en el léxico incluido.")
    }

    private func lemmaFont(_ id: String) -> Font {
        .custom(id.hasPrefix("H") ? "Arial Hebrew" : "Times New Roman", size: 30)
    }

    private func entry(_ e: LexiconEntry) -> some View {
        let hebrew = e.id.hasPrefix("H")
        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text(e.id).font(.system(size: 13, weight: .bold)).monospacedDigit()
                        .padding(.horizontal, 9).padding(.vertical, 3)
                        .background(theme.palette.accent, in: Capsule()).foregroundStyle(theme.palette.onAccent)
                    if let w = state.strongWord {
                        Text("«\(w)»").font(.system(size: 13, design: .serif).italic()).foregroundStyle(theme.palette.textSecondary)
                    }
                    Spacer()
                }
                if let l = e.lemma {
                    Text(l).font(lemmaFont(e.id)).foregroundStyle(theme.palette.textPrimary)
                        .environment(\.layoutDirection, hebrew ? .rightToLeft : .leftToRight)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityLabel("Palabra original \(l)")
                }
                VStack(alignment: .leading, spacing: 2) {
                    if let t = e.translit { Text(t).italic().foregroundStyle(theme.palette.textPrimary) }
                    if let p = e.pronunciation { Text(p).font(.callout).foregroundStyle(theme.palette.textSecondary) }
                }
                if let d = e.definition { section("Definición", d) }
                if let u = e.kjvUsage, !u.isEmpty { section("Uso en KJV", u) }
                Divider().overlay(theme.palette.border)
                occurrences
            }
            .padding(16).textSelection(.enabled)
        }
        .accessibilityLabel("Strong \(e.id), \(e.translit ?? ""), definición: \(e.definition ?? "")")
    }

    private func section(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased()).font(.system(size: 10, weight: .semibold)).foregroundStyle(theme.palette.textMuted)
            Text(body).font(.system(size: 13)).foregroundStyle(theme.palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private var occurrences: some View {
        let total = state.strongOccurrenceTotal
        VStack(alignment: .leading, spacing: 4) {
            Text("OTRAS APARICIONES").font(.system(size: 10, weight: .semibold)).foregroundStyle(theme.palette.textMuted)
            Text(state.strongOccurrences.count < total
                 ? "\(total) versículos (se muestran \(state.strongOccurrences.count))" : "\(total) versículos")
                .font(.callout).foregroundStyle(theme.palette.textSecondary)
        }
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(state.strongOccurrences) { o in
                Button { state.open(ref: o.ref) } label: {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(state.bookName(o.ref.book)) \(o.ref.chapter):\(o.ref.verseFrom ?? 1)")
                            .font(.system(size: 12, weight: .semibold)).foregroundStyle(theme.palette.accent)
                        Text(o.text).font(.system(size: 12)).lineLimit(2).foregroundStyle(theme.palette.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 5).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(state.bookName(o.ref.book)) \(o.ref.chapter):\(o.ref.verseFrom ?? 1). \(o.text)")
                Divider().overlay(theme.palette.border)
            }
        }
    }
}
