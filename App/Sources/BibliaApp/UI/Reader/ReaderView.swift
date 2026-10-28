import SwiftUI
import AppKit

/// S01: lector de capítulo.
struct ReaderView: View {
    @Environment(AppState.self) private var state
    @Environment(\.theme) private var theme

    var body: some View {
        Group {
            if state.items.isEmpty {
                ContentUnavailableView {
                    Label("Capítulo no disponible", systemImage: "book.closed")
                } description: {
                    Text("\(state.currentTranslation?.name ?? state.translationId) no incluye \(state.bookName(state.book)) \(state.chapter). Prueba con otra versión desde la barra de herramientas o navega a otro capítulo.")
                }
                .foregroundStyle(theme.palette.textSecondary)
            } else {
                ChapterScroll().id(state.chapterKey)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.palette.background)
        .overlay(alignment: .bottom) { ToastView() }
    }
}

struct ToastView: View {
    @Environment(AppState.self) private var state
    @Environment(\.theme) private var theme

    var body: some View {
        Group {
            if let t = state.toast {
                Text(t).font(.callout)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(theme.palette.surface, in: Capsule())
                    .overlay(Capsule().stroke(theme.palette.border))
                    .foregroundStyle(theme.palette.textPrimary)
                    .padding(.bottom, 20)
                    .transition(.opacity)
            }
        }
        .task(id: state.toast) {
            guard state.toast != nil else { return }
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            state.toast = nil
        }
    }
}

private struct ChapterScroll: View {
    @Environment(AppState.self) private var state
    @Environment(AppSettings.self) private var settings
    @Environment(\.theme) private var theme
    @State private var topID: Int?
    @State private var tracking = false
    @FocusState private var focused: Bool

    private var blocks: [ReaderBlock] {
        BlockBuilder.build(items: state.items, paragraph: settings.verseLayout == .paragraph,
                           showHeadings: settings.showHeadings)
    }

    var body: some View {
        let blocks = self.blocks
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    Text("\(state.bookName(state.book)) \(state.chapter)")
                        .font(theme.chapterTitleFont)
                        .foregroundStyle(theme.palette.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                        .padding(.bottom, theme.pt * 0.8)
                        .id(-1)
                    ForEach(blocks) { b in
                        BlockView(block: b).id(b.id)
                    }
                }
                .scrollTargetLayout()
                .frame(maxWidth: 760, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.vertical, 28)
                .frame(maxWidth: .infinity)
            }
            .scrollPosition(id: $topID, anchor: .top)
            .focusable()
            .focused($focused)
            .focusEffectDisabled()
            .onKeyPress(.leftArrow) { state.goPrev(); return .handled }
            .onKeyPress(.rightArrow) { state.goNext(); return .handled }
            .onKeyPress(.escape) { state.clearSelection(); return .handled }
            .onAppear { focused = true; scroll(proxy, to: state.scrollRequest.verse, blocks: blocks) }
            .onChange(of: state.scrollRequest) { _, r in scroll(proxy, to: r.verse, blocks: blocks) }
            .onChange(of: settings.fontScale) { _, _ in scroll(proxy, to: state.anchorVerse, blocks: blocks) }
            .onChange(of: settings.verseLayout) { _, _ in scroll(proxy, to: state.anchorVerse, blocks: blocks) }
            .onChange(of: settings.showHeadings) { _, _ in scroll(proxy, to: state.anchorVerse, blocks: blocks) }
            .onChange(of: topID) { _, new in
                guard tracking, let new else { return }
                state.scrolled(toVerse: new < 0 ? (state.items.first?.number ?? 1) : new)
            }
        }
    }

    private func scroll(_ proxy: ScrollViewProxy, to verse: Int, blocks: [ReaderBlock]) {
        // Los bloques pueden cambiar (layout/títulos): recalcular con el estado actual.
        tracking = false
        let anchor = verse
        DispatchQueue.main.async {
            let current = BlockBuilder.build(items: state.items, paragraph: settings.verseLayout == .paragraph,
                                             showHeadings: settings.showHeadings)
            let target = current.first { $0.contains(anchor) }?.id
            let id = (target == nil || target == current.first?.id) ? -1 : target!
            proxy.scrollTo(id, anchor: .top)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { proxy.scrollTo(id, anchor: .top) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { tracking = true }
        }
    }
}

private struct BlockView: View {
    @Environment(AppState.self) private var state
    @Environment(AppSettings.self) private var settings
    @Environment(\.theme) private var theme
    let block: ReaderBlock

    var body: some View {
        let latin = state.isLatin
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(block.headings.enumerated()), id: \.offset) { i, h in
                Text(h)
                    .font(theme.headingFont)
                    .foregroundStyle(theme.palette.heading)
                    .padding(.top, i == 0 ? theme.pt * 1.4 : theme.pt * 0.3)
                    .padding(.bottom, theme.pt * 0.5)
                    .textSelection(.enabled)
                    .accessibilityAddTraits(.isHeader)
            }
            verseText(latin: latin)
        }
        .padding(.top, topGap)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var topGap: CGFloat {
        guard block.headings.isEmpty else { return 0 }
        if settings.verseLayout == .perLine { return theme.verseGap }
        return block.continuation ? 0 : theme.paragraphGap
    }

    @ViewBuilder private func verseText(latin: Bool) -> some View {
        let attr = VerseText.attributed(verses: block.verses, theme: theme, latin: latin,
                                        selected: state.selectedVerses)
        Text(attr)
            .lineSpacing(theme.lineSpacing(latin: latin))
            .tracking(latin ? 0 : theme.pt * 0.02)
            .tint(theme.palette.verseNumber)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                guard settings.verseLayout == .perLine, let v = block.verses.first else { return }
                let m = NSEvent.modifierFlags
                state.clickVerse(v.number, shift: m.contains(.shift), command: m.contains(.command))
            }
            .environment(\.openURL, OpenURLAction { url in
                guard url.scheme == "verse", let n = Int(url.host ?? "") else { return .systemAction }
                let m = NSEvent.modifierFlags
                state.clickVerse(n, shift: m.contains(.shift), command: m.contains(.command))
                return .handled
            })
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(block.verses.map { "Versículo \($0.label). \($0.text)" }.joined(separator: " "))
    }
}

enum VerseText {
    /// Número en superíndice (enlace verse://N para seleccionar) + texto, con selección resaltada.
    static func attributed(verses: [DisplayVerse], theme: Theme, latin: Bool, selected: Set<Int>,
                           links: Bool = true) -> AttributedString {
        var out = AttributedString()
        for (i, v) in verses.enumerated() {
            let isSel = selected.contains(v.number)
            var num = AttributedString(v.label + "\u{2009}")
            num.font = theme.verseNumberFont
            num.baselineOffset = theme.verseNumberBaseline
            num.foregroundColor = theme.palette.verseNumber
            if links { num.link = URL(string: "verse://\(v.number)") }
            var body = AttributedString(v.text)
            body.font = theme.readingFont(latin: latin)
            body.foregroundColor = theme.palette.textPrimary
            if isSel {
                num.backgroundColor = theme.palette.selection
                body.backgroundColor = theme.palette.selection
            }
            out += num
            out += body
            if i < verses.count - 1 { out += AttributedString(latin ? " " : "") }
        }
        return out
    }
}
