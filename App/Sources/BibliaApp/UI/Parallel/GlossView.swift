import BibliaCore
import SwiftUI
import AppKit

/// Un versículo del modo «Principal + glosas»: lectura normal de la principal (títulos, poesía, número una vez)
/// y, debajo, una línea pequeña, sangrada y gris por glosa, con la sigla en el color de acento de la versión.
struct GlossGroupView: View {
    @Environment(AppState.self) private var state
    @Environment(\.theme) private var theme
    let group: GlossGroup
    let allBlocks: [BookBlock]

    var body: some View {
        let selected = state.selectedVerses.contains(group.number)
        VStack(alignment: .leading, spacing: 0) {
            if group.primaryMissing {
                Text("\(group.number)\u{2009}\u{2014}")
                    .font(.system(size: theme.pt * 0.85)).foregroundStyle(theme.palette.textMuted)
                    .padding(.top, theme.pt * 0.9)
                    .accessibilityLabel("Versículo \(group.number) no existe en la versión principal")
            }
            ForEach(group.blocks) { b in
                let prev = b.id > 0 ? allBlocks[safe: b.id - 1] : nil
                BlockView(block: b, prev: prev, perVerse: false, gapOverride: gap(for: b, prev: prev))
            }
            VStack(alignment: .leading, spacing: theme.pt * 0.18) {
                ForEach(group.glosses) { g in GlossLineView(line: g, selected: selected) }
            }
            .padding(.top, group.glosses.isEmpty ? 0 : theme.pt * 0.4)
            .contentShape(Rectangle())
            .onTapGesture {
                let m = NSEvent.modifierFlags
                state.clickVerse(group.number, shift: m.contains(.shift), command: m.contains(.command))
            }
            .contextMenu { VerseMenuItems(scope: state.scope(forContextVerse: group.number)) }
        }
    }

    /// Aire generoso entre versículos; dentro de un versículo (líneas de poesía) manda la separación normal.
    private func gap(for b: BookBlock, prev: BookBlock?) -> CGFloat? {
        guard let prev, b.kind != .heading, prev.kind != .heading, b.pieces.first?.label != nil else { return nil }
        return theme.pt * 1.0
    }
}

struct GlossLineView: View {
    @Environment(\.theme) private var theme
    @Environment(AppState.self) private var state
    let line: GlossLine
    let selected: Bool

    private var latin: Bool { line.language != "zh" }
    private var size: CGFloat { Theme.baseSize * 0.82 }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(line.translationId)
                .font(.system(size: theme.pt * 0.66, weight: .bold).smallCaps())
                .tracking(0.4)
                .foregroundStyle(versionAccent(line.versionIndex, theme))
                .frame(width: theme.pt * 3.0, alignment: .leading)
                .lineLimit(1)
            switch line.content {
            case .text(let v):
                Text(attributed(v))
                    .lineSpacing(theme.lineSpacing(latin: latin) * 0.7)
                    .tracking(latin ? 0 : theme.pt * 0.02)
                    .frame(maxWidth: .infinity, alignment: .leading)
            case .merged(let label):
                Text("(\(label))")
                    .font(.system(size: theme.pt * 0.82)).foregroundStyle(theme.palette.textMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.leading, theme.pt * 1.5)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }

    private var label: String {
        let name = state.translations.first { $0.id == line.translationId }?.name ?? line.translationId
        switch line.content {
        case .text(let v): return "\(name). Versículo \(v.label). \(v.text)"
        case .merged(let l): return "\(name). Incluido en el versículo \(l)"
        }
    }

    private func attributed(_ v: DisplayVerse) -> AttributedString {
        var out = AttributedString()
        if v.endNumber > v.number {
            var r = AttributedString("\(v.label)\u{2009}")
            r.font = .system(size: theme.pt * 0.6, weight: .semibold).monospacedDigit()
            r.foregroundColor = theme.palette.textMuted
            out += r
        }
        var body = AttributedString(v.text)
        body.font = theme.readingFont(latin: latin, size: size)
        body.foregroundColor = theme.palette.textSecondary
        out += body
        return out
    }
}

/// Aviso discreto cuando el modo intercalado no tiene glosas elegidas.
struct GlossPrompt: View {
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 8) {
            Text("Sin glosas: solo se lee la versión principal.")
                .font(.system(size: 13)).foregroundStyle(theme.palette.textMuted)
            GlossMenu(title: "Elegir glosas")
        }
        .padding(.bottom, theme.pt * 0.6)
    }
}

/// Menú «Glosas»: versiones agrupadas por idioma (máx. 3, sin la principal) y el interruptor global.
struct GlossMenu: View {
    @Environment(AppState.self) private var state
    var title = "Glosas"

    var body: some View {
        Menu {
            ForEach(GlossSet.grouped(state.translations, primary: state.translationId), id: \.language) { group in
                Section(languageName(group.language)) {
                    ForEach(group.items) { t in
                        Toggle("\(t.id) · \(t.name)", isOn: Binding(get: { state.glossSet.contains(t.id) },
                                                                    set: { _ in state.toggleGloss(t.id) }))
                            .disabled(!state.glossSet.canAdd(t.id, primary: state.translationId))
                    }
                }
            }
            Divider()
            Toggle("Mostrar glosas", isOn: Binding(get: { state.showGlosses }, set: { state.setShowGlosses($0) }))
            Text("Máximo \(GlossSet.maxGlosses) glosas")
        } label: {
            Text(title)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Elegir las versiones que aparecen como glosas (máx. \(GlossSet.maxGlosses))")
        .accessibilityLabel(title)
    }
}
