import BibliaCore
import SwiftUI

/// S06: inspector Strong (léxico + otras apariciones).
struct StrongPanel: View {
    @Environment(AppState.self) private var state
    @Environment(\.theme) private var theme
    /// «Buscar todas las apariciones»: despliega la lista de versículos con ese número.
    @State private var showOccurrences = false

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
        .onChange(of: state.strongId) { _, _ in showOccurrences = false }
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

    @ViewBuilder private func lemmaText(_ l: String, hebrew: Bool) -> some View {
        let f: Font = hebrew ? .custom("Arial Hebrew", size: 40) : theme.serifFont(size: 40)
        Text(l).font(f).foregroundStyle(theme.palette.textPrimary).lineLimit(1).minimumScaleFactor(0.5)
            .environment(\.layoutDirection, hebrew ? .rightToLeft : .leftToRight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel("Palabra original \(l)")
    }

    private func entry(_ e: LexiconEntry) -> some View {
        let hebrew = e.id.hasPrefix("H")
        let kjv = state.strongTranslationId ?? "KJV"
        return ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(e.id).font(theme.uiFont(size: 13, weight: .bold)).monospacedDigit()
                            .padding(.horizontal, 9).padding(.vertical, 3)
                            .background(theme.palette.accent, in: Capsule()).foregroundStyle(theme.palette.onAccent)
                        if let w = state.strongWord {
                            Text("«\(w)»").font(theme.serifFont(size: 13, italic: true)).foregroundStyle(theme.palette.textSecondary)
                        }
                        Spacer()
                    }
                    if let c = state.strongContext {
                        (Text(c.before) + Text(c.word).bold().foregroundColor(theme.palette.textPrimary) + Text(c.after))
                            .font(theme.serifFont(size: 12)).foregroundStyle(theme.palette.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityLabel("En contexto, versículo \(c.verse): \(c.before)\(c.word)\(c.after)")
                    }
                    if let l = e.lemma { lemmaText(l, hebrew: hebrew) }
                    VStack(alignment: .leading, spacing: 2) {
                        if let t = e.translit { Text(t).font(theme.serifFont(size: 15, italic: true)).foregroundStyle(theme.palette.textPrimary) }
                        if let p = e.pronunciation { Text(p).font(theme.uiFont(size: 13)).italic().foregroundStyle(theme.palette.textSecondary) }
                    }
                    if let d = e.definition { section("Definición", d) }
                    if let u = e.kjvUsage, !u.isEmpty { section("Traducido en la \(kjv) como", u) }
                    Button {
                        showOccurrences.toggle()
                        if showOccurrences { withAnimation { proxy.scrollTo("occurrences", anchor: .top) } }
                    } label: {
                        Text("Buscar todas las apariciones de \(e.id) \u{2192}")
                            .font(theme.uiFont(size: 13, weight: .medium)).foregroundStyle(theme.palette.accent)
                            .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Buscar todas las apariciones de \(e.id)")
                    if showOccurrences { VStack(alignment: .leading, spacing: 8) { occurrences }.id("occurrences") }
                    wordCapsules
                }
                .padding(16).textSelection(.enabled)
            }
        }
        .accessibilityLabel("Strong \(e.id), \(e.translit ?? ""), definición: \(e.definition ?? "")")
    }

    /// Título en versalitas (small caps) sobre cuerpo de texto.
    private func sectionTitle(_ t: String) -> some View {
        Text(t).font(theme.uiFont(size: 12, weight: .semibold).smallCaps()).tracking(0.8)
            .foregroundStyle(theme.palette.textMuted)
    }

    private func section(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionTitle(title)
            Text(body).font(theme.uiFont(size: 13)).foregroundStyle(theme.palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Las demás palabras con número del versículo: cada cápsula abre su entrada.
    @ViewBuilder private var wordCapsules: some View {
        if let sel = state.strongSelection {
            let caps = StrongVerseWords.capsules(spans: state.strongSpans[sel.verse] ?? [], active: sel)
            if !caps.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    sectionTitle("Otras palabras del versículo")
                    CapsuleFlow(spacing: 6) {
                        ForEach(caps) { c in
                            Button {
                                if let sp = state.strongSpans[sel.verse]?.first(where: { $0.start == c.start }),
                                   let u = StrongLink.url(sp, verse: sel.verse) { state.openStrong(link: u) }
                            } label: {
                                Text(c.word).font(theme.uiFont(size: 12))
                                    .foregroundStyle(theme.palette.textPrimary)
                                    .padding(.horizontal, 10).padding(.vertical, 4)
                                    .overlay(Capsule().strokeBorder(theme.palette.border, lineWidth: 1))
                                    .contentShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Palabra \(c.word), \(c.strong)")
                        }
                    }
                }
            }
        }
    }

    /// Libro en el idioma de la versión de las apariciones (KJV -> inglés) + versión.
    private func occurrenceTitle(_ o: StrongOccurrence) -> String {
        "\(BookNameLanguage.name(o.ref.book, language: state.strongLanguage)) \(o.ref.chapter):\(o.ref.verseFrom ?? 1) (\(state.strongTranslationId ?? "KJV"))"
    }

    @ViewBuilder private var occurrences: some View {
        let total = state.strongOccurrenceTotal
        VStack(alignment: .leading, spacing: 4) {
            sectionTitle("Apariciones · \(state.strongTranslationId ?? "KJV")")
            Text(state.strongOccurrences.count < total
                 ? "\(total) versículos (se muestran \(state.strongOccurrences.count))" : "\(total) versículos")
                .font(.callout).foregroundStyle(theme.palette.textSecondary)
        }
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(state.strongOccurrences) { o in
                Button { state.open(ref: o.ref) } label: {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(occurrenceTitle(o))
                            .font(.system(size: 12, weight: .semibold)).foregroundStyle(theme.palette.accent)
                        Text(o.text).font(.system(size: 12)).lineLimit(2).foregroundStyle(theme.palette.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 5).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(occurrenceTitle(o)). \(o.text)")
                Divider().overlay(theme.palette.border)
            }
        }
    }
}

/// Cápsulas en filas que saltan de línea.
struct CapsuleFlow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width ?? .infinity, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let r = arrange(width: bounds.width, subviews: subviews)
        for (i, f) in r.frames.enumerated() {
            subviews[i].place(at: CGPoint(x: bounds.minX + f.minX, y: bounds.minY + f.minY), proposal: ProposedViewSize(f.size))
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> (size: CGSize, frames: [CGRect]) {
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, maxW: CGFloat = 0
        var frames: [CGRect] = []
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0, x + s.width > width { x = 0; y += rowH + spacing; rowH = 0 }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: s))
            x += s.width + spacing; rowH = max(rowH, s.height); maxW = max(maxW, x - spacing)
        }
        return (CGSize(width: maxW, height: y + rowH), frames)
    }
}
