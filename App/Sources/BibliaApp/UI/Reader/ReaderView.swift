import BibliaCore
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
        .overlay(alignment: .topTrailing) { SearchTermsChip() }
        .verseActionBarDock()
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

    private func makeBlocks() -> [BookBlock] {
        ChapterBuilder.blocks(items: state.items, layout: state.layout,
                              mode: settings.verseLayout == .paragraph ? .book : .perVerse,
                              showHeadings: settings.showHeadings)
    }

    var body: some View {
        let blocks = makeBlocks()
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ChapterHeaderView(bookName: state.bookName(state.book), chapter: state.chapter)
                        .padding(.top, 20).padding(.bottom, theme.pt * 0.9)
                        .id(-1)
                    ForEach(blocks) { b in
                        BlockView(block: b, prev: b.id > 0 ? blocks[b.id - 1] : nil,
                                  perVerse: settings.verseLayout == .perLine)
                            .id(b.id)
                    }
                    ChapterEndNav()
                }
                .scrollTargetLayout()
                .frame(maxWidth: Theme.readingColumnWidth, alignment: .leading)
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
            .onKeyPress(.escape) { state.clearSelection(); state.clearFlash(); return .handled }
            .onAppear { focused = true; scroll(proxy, to: state.scrollRequest.verse) }
            .onChange(of: state.scrollRequest) { _, r in scroll(proxy, to: r.verse) }
            .onChange(of: settings.fontScale) { _, _ in scroll(proxy, to: state.anchorVerse) }
            .onChange(of: settings.verseLayout) { _, _ in scroll(proxy, to: state.anchorVerse) }
            .onChange(of: settings.showHeadings) { _, _ in scroll(proxy, to: state.anchorVerse) }
            .onChange(of: state.actionBarVisible) { _, on in if on { reveal(proxy) } }
            .onChange(of: state.actionBarVerse) { _, _ in if state.actionBarVisible { reveal(proxy) } }
            .onChange(of: topID) { _, new in
                guard tracking, let new else { return }
                if new < 0 { state.scrolled(toVerse: state.items.first?.number ?? 1) }
                else if let b = blocks[safe: new] { state.scrolled(toVerse: b.anchorVerse) }
            }
        }
    }

    /// La barra inferior reduce el área visible: desplaza lo mínimo para que el versículo siga a la vista.
    private func reveal(_ proxy: ScrollViewProxy) {
        let verse = state.actionBarVerse
        tracking = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            if let id = ChapterBuilder.blockID(for: verse, in: makeBlocks()) { proxy.scrollTo(id) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { tracking = true }
        }
    }

    private func scroll(_ proxy: ScrollViewProxy, to verse: Int) {
        tracking = false
        DispatchQueue.main.async {
            let current = makeBlocks()
            var id = ChapterBuilder.blockID(for: verse, in: current) ?? -1
            if id == (current.first { $0.kind != .heading }?.id ?? 0) && verse <= (state.items.first?.number ?? 1) { id = -1 }
            proxy.scrollTo(id, anchor: .top)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { proxy.scrollTo(id, anchor: .top) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { tracking = true }
        }
    }
}

struct BlockView: View {
    @Environment(AppState.self) private var state
    @Environment(\.theme) private var theme
    let block: BookBlock
    let prev: BookBlock?
    let perVerse: Bool
    /// Separación superior fija (modo glosas: aire generoso entre versículos).
    var gapOverride: CGFloat?

    var body: some View {
        let latin = state.isLatin
        switch block.kind {
        case .heading: heading
        case .blank: Color.clear.frame(height: theme.pt * 0.7).accessibilityHidden(true)
        case .prose, .poetry, .list: text(latin: latin)
        }
    }

    private var heading: some View {
        let k = block.headingKind
        let size: Double, weight: Font.Weight, italic: Bool, center: Bool, color: Color
        switch k {
        case "ms": (size, weight, italic, center, color) = (1.15, .bold, false, true, theme.palette.heading)
        case "s2": (size, weight, italic, center, color) = (0.85, .semibold, true, false, theme.palette.heading)
        case "d": (size, weight, italic, center, color) = (0.92, .regular, true, false, theme.palette.textSecondary)
        case "r": (size, weight, italic, center, color) = (0.78, .regular, true, false, theme.palette.textMuted)
        default: (size, weight, italic, center, color) = (0.92, .semibold, false, false, theme.palette.heading)
        }
        let top: CGFloat = (prev == nil) ? 0 : (k == "d" || k == "r" ? theme.pt * 0.15 : theme.pt * (k == "ms" ? 1.8 : 1.4))
        let f = theme.serifFont(size: theme.pt * size, weight: weight == .bold || weight == .semibold ? .semibold : .regular,
                                italic: italic)
        return Text(block.pieces.first?.text ?? "")
            .font(f)
            .foregroundStyle(color)
            .multilineTextAlignment(center ? .center : .leading)
            .frame(maxWidth: .infinity, alignment: center ? .center : .leading)
            .padding(.top, top)
            .padding(.bottom, theme.pt * (k == "r" || k == "d" ? 0.3 : 0.5))
            .textSelection(.enabled)
            .accessibilityAddTraits(.isHeader)
    }

    private var topGap: CGFloat {
        if let g = gapOverride { return g }
        guard let prev else { return 0 }
        if perVerse { return prev.kind == .heading ? 0 : theme.verseGap }
        switch block.kind {
        case .poetry, .list:
            return prev.kind == .poetry || prev.kind == .list || prev.kind == .blank ? theme.pt * 0.08 :
                   prev.kind == .heading ? 0 : theme.pt * 0.5
        default:
            return prev.kind == .heading || prev.kind == .blank ? 0 : theme.pt * (block.flush ? 0.5 : 0.7)
        }
    }

    private var indent: CGFloat {
        switch block.kind {
        case .poetry: return theme.pt * 1.5 * CGFloat(max(0, block.level - 1)) + theme.pt * 0.4
        case .list: return theme.pt * 1.2 * CGFloat(block.level)
        default: return 0
        }
    }

    /// Sangría francesa (líneas que no caben): 1,5 em más que la primera línea.
    private var hang: CGFloat { block.kind == .poetry || block.kind == .list ? theme.pt * 1.5 : 0 }

    @ViewBuilder private func text(latin: Bool) -> some View {
        let attr = VerseText.attributed(pieces: block.pieces, theme: theme, latin: latin,
                                        selected: state.selectedVerses, hang: hang,
                                        hl: state.highlight(for: state.translationId))
        let single = block.verseNumbers.count == 1 ? block.verseNumbers.first : nil
        let spacing = theme.lineSpacing(latin: latin)
        let tracking = latin ? 0 : theme.pt * 0.02
        // Fondos (resaltado, selección, palabra Strong activa) con esquinas redondeadas: se dibujan detrás del texto.
        let rounded = attr.hasRoundedBackgrounds
        Text(rounded ? attr.strippingRoundedBackgrounds() : attr)
            .lineSpacing(spacing)
            .tracking(tracking)
            .tint(theme.palette.verseNumber)
            // Sin .textSelection: en macOS convierte el clic en selección de letras y los enlaces
            // verse:// (clic → seleccionar versículo + barra de acciones) dejan de recibirse.
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if rounded {
                    RoundedBackdrop(attr: attr, bodyFont: theme.readingNSFont(latin: latin),
                                    lineSpacing: spacing, tracking: tracking)
                }
            }
            .padding(.leading, indent)
            .contentShape(Rectangle())
            .environment(\.openURL, OpenURLAction { url in
                if url.scheme == StrongLink.scheme { state.openStrong(link: url); return .handled }
                if let id = NoteLink.parse(url) { state.openNoteIcon(id: id); return .handled }
                guard url.scheme == "verse", let n = Int(url.host ?? "") else { return .systemAction }
                let m = NSEvent.modifierFlags
                state.clickVerse(n, shift: m.contains(.shift), command: m.contains(.command))
                return .handled
            })
            .contextMenu { VerseMenuItems(scope: state.scope(forContextVerse: single)) }
            .padding(.top, topGap)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(block.pieces.map { p in
                (p.label.map { "Versículo \($0). " } ?? "") + p.text }.joined(separator: " "))
    }
}

/// Resaltado dentro del texto: coincidencias de búsqueda (persistentes) y versículos destacados (se desvanecen).
struct TextHighlight: Equatable {
    var terms: [String] = []
    var flash: Set<Int> = []
    var flashAlpha: Double = 0
    /// Modo Strong: tramos por versículo y palabra abierta en el inspector.
    var strongSpans: [Int: [StrongSpan]] = [:]
    var strongActive: StrongSelection?
    /// Resaltados, marcadores y notas del capítulo (por referencia: valen para cualquier versión).
    var ann = ChapterAnnotations()
    static let none = TextHighlight()

    /// Anotaciones de un versículo o grupo fusionado; `nil` si no hay ninguna.
    func annotations(_ from: Int, _ to: Int) -> VerseAnnotations? {
        guard !(ann.highlights.isEmpty && ann.notes.isEmpty && ann.bookmarks.isEmpty) else { return nil }
        let a = ann.forDisplayVerse(number: from, end: to)
        return a.isEmpty ? nil : a
    }

    func flashes(_ from: Int, _ to: Int) -> Bool { flashAlpha > 0 && flash.contains { $0 >= from && $0 <= to } }

    /// Subrayado punteado + enlace en cada palabra con número, dentro del trozo `[offset, offset+count)` del versículo.
    func applyStrong(to body: inout AttributedString, verse: Int, offset: Int, count: Int, theme: Theme) {
        guard offset >= 0, let spans = strongSpans[verse] else { return }
        for sp in spans where sp.start >= offset && sp.end <= offset + count {
            let a = sp.start - offset, b = sp.end - offset
            let chars = body.characters
            guard let lo = chars.index(chars.startIndex, offsetBy: a, limitedBy: chars.endIndex),
                  let hi = chars.index(chars.startIndex, offsetBy: b, limitedBy: chars.endIndex), lo < hi else { continue }
            let active = strongActive == StrongSelection(strong: sp.strong, verse: verse, start: sp.start)
            // Palabra con número: subrayado punteado fino (sin negrita ni color). Activa: fondo accent + texto onAccent.
            if active {
                body[lo..<hi].foregroundColor = theme.palette.onAccent
                body[lo..<hi].backgroundColor = theme.palette.accent
                body[lo..<hi][RoundedBGKey.self] = RoundedBG(color: theme.palette.accent, radius: 3)
            } else {
                body[lo..<hi].underlineStyle = Text.LineStyle(pattern: .dot, color: theme.palette.strongUnderline)
            }
            if let u = StrongLink.url(sp, verse: verse) { body[lo..<hi].link = u }
        }
    }

    /// Coincidencias de búsqueda: fondo + negrita + subrayado, para distinguirlas de un resaltado amarillo del usuario.
    func apply(to body: inout AttributedString, plain: String, theme: Theme, latin: Bool = true) {
        guard !terms.isEmpty else { return }
        for r in SearchHighlighter.ranges(in: plain, terms: terms) {
            if let lo = AttributedString.Index(r.lowerBound, within: body),
               let hi = AttributedString.Index(r.upperBound, within: body) {
                body[lo..<hi].backgroundColor = theme.palette.searchHighlight
                body[lo..<hi].foregroundColor = theme.palette.textPrimary
                body[lo..<hi].font = theme.readingFont(latin: latin, weight: .semibold)
                body[lo..<hi][MirrorFontKey.self] = theme.readingNSFont(latin: latin, weight: .semibold)
                body[lo..<hi].underlineStyle = .single
            }
        }
    }
}

enum VerseText {
    private static func numberRun(_ label: String, verse: Int, theme: Theme, selected: Bool, links: Bool,
                                  band: RoundedBG? = nil) -> AttributedString {
        var num = AttributedString(label + "\u{2009}\u{2060}")   // U+2060: el número no se queda solo al final de línea
        num.font = theme.verseNumberFont
        num[MirrorFontKey.self] = theme.verseNumberNSFont
        num.baselineOffset = theme.verseNumberBaseline
        num.foregroundColor = theme.palette.verseNumber
        if links { num.link = URL(string: "verse://\(verse)") }
        if selected { num.backgroundColor = theme.palette.selection }
        if let band { num[RoundedBGKey.self] = band }
        return num
    }

    /// Fondo redondeado del cuerpo (4 pt si está seleccionado, 3 pt si es un resaltado).
    private static func band(_ c: HighlightColor?, selected: Bool, flash: Double, theme: Theme) -> RoundedBG? {
        if let bg = bodyBackground(c, selected: selected, theme: theme) {
            return RoundedBG(color: bg, radius: selected ? 4 : 3)
        }
        if flash > 0 { return RoundedBG(color: theme.palette.selection.opacity(flash), radius: 4) }
        return nil
    }

    /// Fuente del cuerpo + su copia AppKit para medir.
    private static func setBodyFont(_ body: inout AttributedString, theme: Theme, latin: Bool) {
        body.font = theme.readingFont(latin: latin)
        body[MirrorFontKey.self] = theme.readingNSFont(latin: latin)
    }

    /// Marcador: pequeño glifo antes del número del versículo.
    static func bookmarkGlyph(theme: Theme) -> AttributedString {
        var g = AttributedString("\u{2691}\u{2009}")
        g.font = .system(size: theme.pt * 0.8, weight: .bold)
        g[MirrorFontKey.self] = NSFont.systemFont(ofSize: theme.pt * 0.8, weight: .bold)
        g.baselineOffset = theme.verseNumberBaseline
        g.foregroundColor = theme.palette.bookmarkMarker
        return g
    }

    /// Nota: glifo tras el versículo; al pulsarlo se abre la nota (enlace note://ID).
    static func noteGlyph(_ n: Note, theme: Theme) -> AttributedString {
        var g = AttributedString("\u{2009}\u{270E}")
        g.font = .system(size: theme.pt * 0.78, weight: .semibold)
        g[MirrorFontKey.self] = NSFont.systemFont(ofSize: theme.pt * 0.78, weight: .semibold)
        g.foregroundColor = theme.palette.accent
        g.link = URL(string: "\(NoteLink.scheme)://\(n.id)")
        return g
    }

    /// Fondo del cuerpo del versículo: la selección gana, pero se mezcla con el color de resaltado.
    private static func bodyBackground(_ c: HighlightColor?, selected: Bool, theme: Theme) -> Color? {
        if selected { return c.flatMap { theme.palette.highlightSelected[$0] } ?? theme.palette.selection }
        return c.flatMap { theme.palette.highlight[$0] }
    }

    /// Número en superíndice (enlace verse://N para seleccionar) + texto, con selección resaltada.
    static func attributed(verses: [DisplayVerse], theme: Theme, latin: Bool, selected: Set<Int>,
                           links: Bool = true, hl: TextHighlight = .none) -> AttributedString {
        var out = AttributedString()
        for (i, v) in verses.enumerated() {
            let isSel = selected.contains(v.number)
            let va = hl.annotations(v.number, v.endNumber)
            var body = AttributedString(v.text)
            setBodyFont(&body, theme: theme, latin: latin)
            body.foregroundColor = theme.palette.textPrimary
            if let bg = bodyBackground(va?.color, selected: isSel, theme: theme) { body.backgroundColor = bg }
            if !isSel, hl.flashes(v.number, v.endNumber) { body.backgroundColor = theme.palette.selection.opacity(hl.flashAlpha) }
            let bnd = band(va?.color, selected: isSel, flash: !isSel && hl.flashes(v.number, v.endNumber) ? hl.flashAlpha : 0, theme: theme)
            if let bnd { body[RoundedBGKey.self] = bnd }
            hl.apply(to: &body, plain: v.text, theme: theme, latin: latin)
            hl.applyStrong(to: &body, verse: v.number, offset: 0, count: v.text.count, theme: theme)
            if va?.isBookmarked == true { out += bookmarkGlyph(theme: theme) }
            out += numberRun(v.label, verse: v.number, theme: theme, selected: isSel, links: links, band: bnd)
            out += body
            for n in va?.notes ?? [] where n.verseStart >= v.number && n.verseStart <= v.endNumber {
                out += noteGlyph(n, theme: theme)
            }
            if i < verses.count - 1 { out += AttributedString(latin ? " " : "") }
        }
        return out
    }

    /// Trozos de un bloque: número solo donde empieza cada versículo (`label`), texto corrido.
    static func attributed(pieces: [Piece], theme: Theme, latin: Bool, selected: Set<Int>,
                           hang: CGFloat = 0, links: Bool = true, hl: TextHighlight = .none) -> AttributedString {
        var out = AttributedString()
        for (i, p) in pieces.enumerated() {
            let isSel = selected.contains(p.verse)
            let va = hl.annotations(p.verse, p.end)
            if p.label != nil, va?.isBookmarked == true { out += bookmarkGlyph(theme: theme) }
            let bnd = band(va?.color, selected: isSel, flash: !isSel && hl.flashes(p.verse, p.end) ? hl.flashAlpha : 0, theme: theme)
            if let l = p.label { out += numberRun(l, verse: p.verse, theme: theme, selected: isSel, links: links, band: bnd) }
            var body = AttributedString(p.text)
            setBodyFont(&body, theme: theme, latin: latin)
            body.foregroundColor = theme.palette.textPrimary
            if let bg = bodyBackground(va?.color, selected: isSel, theme: theme) { body.backgroundColor = bg }
            if !isSel, hl.flashes(p.verse, p.end) { body.backgroundColor = theme.palette.selection.opacity(hl.flashAlpha) }
            if let bnd { body[RoundedBGKey.self] = bnd }
            hl.apply(to: &body, plain: p.text, theme: theme, latin: latin)
            hl.applyStrong(to: &body, verse: p.verse, offset: p.textOffset, count: p.text.count, theme: theme)
            if links, body.link == nil { body.link = URL(string: "verse://\(p.verse)") }
            out += body
            let lastOfVerse = i == pieces.count - 1 || pieces[i + 1].verse != p.verse
            if lastOfVerse {
                for n in va?.notes ?? [] where n.verseStart >= p.verse && n.verseStart <= p.end {
                    out += noteGlyph(n, theme: theme)
                }
            }
            if i < pieces.count - 1 {
                var sep = AttributedString(latin ? " " : "")
                // El espacio entre dos trozos del mismo versículo lleva el mismo fondo (banda continua).
                if let bnd, pieces[i + 1].verse == p.verse { sep[RoundedBGKey.self] = bnd }
                out += sep
            }
        }
        if hang > 0 {
            let ps = NSMutableParagraphStyle()
            ps.firstLineHeadIndent = 0
            ps.headIndent = hang
            out[AttributeScopes.AppKitAttributes.ParagraphStyleAttribute.self] = ps
        }
        return out
    }
}

/// Cabecera de capítulo: nombre del libro en mayúsculas pequeñas y, debajo, el número grande en acento.
struct ChapterHeaderView: View {
    @Environment(\.theme) private var theme
    let bookName: String
    let chapter: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(bookName.uppercased())
                .font(theme.chapterBookFont)
                .tracking(Theme.chapterBookTracking)
                .foregroundStyle(theme.palette.textMuted)
            Text("\(chapter)")
                .font(theme.chapterNumberFont)
                .foregroundStyle(theme.palette.accent)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(bookName) \(chapter)")
        .accessibilityAddTraits(.isHeader)
    }
}

/// Navegación discreta al final del capítulo: «← Juan 2» y «Juan 4 →» (nombres en el idioma de la versión).
private struct ChapterEndNav: View {
    @Environment(AppState.self) private var state
    @Environment(\.theme) private var theme

    private func label(_ p: ChapterPosition) -> String { "\(state.bookName(p.book)) \(p.chapter)" }

    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(theme.palette.border).frame(height: 1)
            HStack(alignment: .firstTextBaseline) {
                if let p = state.prevPosition {
                    Button { state.goPrev() } label: { Text("\u{2190} \(label(p))") }
                        .help("Capítulo anterior (\u{2190})")
                        .accessibilityLabel("Capítulo anterior: \(label(p))")
                }
                Spacer(minLength: 12)
                if let p = state.nextPosition {
                    Button { state.goNext() } label: { Text("\(label(p)) \u{2192}") }
                        .help("Capítulo siguiente (\u{2192})")
                        .accessibilityLabel("Capítulo siguiente: \(label(p))")
                }
            }
            .buttonStyle(ChapterNavButtonStyle())
            .padding(.top, 14)
        }
        .padding(.top, theme.pt * 2)
        .padding(.bottom, 24)
    }
}

private struct ChapterNavButtonStyle: ButtonStyle {
    @Environment(\.theme) private var theme
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(configuration.isPressed ? theme.palette.accent : theme.palette.textSecondary)
            .contentShape(Rectangle())
    }
}
