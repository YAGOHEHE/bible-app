import BibliaCore
import SwiftUI
import AppKit

/// S03: vista paralela. Una sola lista de filas por versículo con N celdas (desplazamiento sincronizado).
struct ParallelView: View {
    @Environment(AppState.self) private var state
    @Environment(\.theme) private var theme

    var body: some View {
        Group {
            if !state.glossMode && state.parallelColumns.count < 2 {
                ContentUnavailableView {
                    Label("Activa otra versión para comparar", systemImage: "rectangle.split.2x1")
                } description: {
                    Text("La vista paralela necesita al menos dos versiones activas. Actívalas en el gestor de versiones.")
                } actions: {
                    Button("Abrir gestor de versiones") { state.showVersions = true }
                }
                .foregroundStyle(theme.palette.textSecondary)
            } else if (state.glossMode ? state.glossRows : state.parallelRows).isEmpty {
                ContentUnavailableView {
                    Label("Capítulo no disponible", systemImage: "book.closed")
                } description: {
                    Text("Ninguna de las versiones activas incluye \(state.bookName(state.book)) \(state.chapter).")
                }
                .foregroundStyle(theme.palette.textSecondary)
            } else {
                GeometryReader { geo in
                    // BUG-002: ancho realmente disponible (tras barra lateral e inspector), no el de la ventana.
                    ParallelContent(stacked: ParallelMetrics.isStacked(availableWidth: geo.size.width,
                                                                       columns: state.parallelColumns.count,
                                                                       layout: state.parallelLayout))
                }
                .id(state.chapterKey + state.parallelColumns.map(\.id).joined() + state.glossColumns.map(\.id).joined()
                    + (state.glossMode ? "g" : "c"))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.palette.background)
        .overlay(alignment: .bottom) { ToastView() }
        .overlay(alignment: .topTrailing) { SearchTermsChip() }
        .verseActionBarDock()
    }
}

enum ParallelMetrics {
    static let minColumn: CGFloat = 300
    static let columnGap: CGFloat = 8
    static let sidePadding: CGFloat = 48

    /// Ancho por columna dado el ancho disponible del panel de lectura.
    static func columnWidth(availableWidth: CGFloat, columns: Int) -> CGFloat {
        let n = CGFloat(max(1, columns))
        return (availableWidth - sidePadding - (n - 1) * columnGap) / n
    }

    /// ¿Disposición apilada? Si el usuario eligió intercalado o cada columna cabría en < 300 pt.
    static func isStacked(availableWidth: CGFloat, columns: Int, layout: ParallelLayout) -> Bool {
        layout == .interleaved || columnWidth(availableWidth: availableWidth, columns: columns) < minColumn
    }
}

private struct ParallelContent: View {
    @Environment(AppState.self) private var state
    @Environment(AppSettings.self) private var settings
    @Environment(\.theme) private var theme
    let stacked: Bool
    @State private var topID: Int?
    @State private var tracking = false
    @FocusState private var focused: Bool

    /// Estilo «Principal + glosas»: el intercalado, y el apilado de Columnas en ventana estrecha.
    private var glossStyle: Bool { state.glossMode || stacked }
    private var source: (rows: [ParallelRow], cols: [Translation]) {
        state.glossMode ? (state.glossRows, state.glossColumns) : (state.parallelRows, state.parallelColumns)
    }
    private func groups() -> [GlossGroup] {
        let src = source
        let blocks = ChapterBuilder.blocks(items: state.items, layout: state.layout, mode: .book, showHeadings: settings.showHeadings)
        return GlossBuilder.groups(rows: src.rows, blocks: blocks, columns: src.cols.map { ($0.id, $0.language) },
                                   showGlosses: state.showGlosses)
    }
    private func numbers(_ g: [GlossGroup]) -> [Int] { glossStyle ? g.map(\.number) : state.parallelRows.map(\.number) }

    var body: some View {
        let gs = glossStyle ? groups() : []
        let nums = numbers(gs)
        let flat = gs.flatMap(\.blocks)
        VStack(spacing: 0) {
            if !glossStyle { ColumnHeaders() }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        Text("\(state.bookName(state.book)) \(state.chapter)")
                            .font(theme.chapterTitleFont)
                            .foregroundStyle(theme.palette.textPrimary)
                            .accessibilityAddTraits(.isHeader)
                            .padding(.bottom, theme.pt * (glossStyle ? 0.8 : 0.6))
                            .id(-1)
                        if state.glossMode && state.glossSet.effective(primary: state.translationId).isEmpty {
                            GlossPrompt()
                        }
                        if glossStyle {
                            ForEach(gs) { g in
                                GlossGroupView(group: g, allBlocks: flat)
                                    .id(g.number)
                            }
                        } else {
                            ForEach(state.parallelRows) { row in
                                ParallelRowView(row: row).id(row.number)
                            }
                        }
                    }
                    .scrollTargetLayout()
                    .frame(maxWidth: glossStyle ? 760 : .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.vertical, glossStyle ? 28 : 20)
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
                .onChange(of: stacked) { _, _ in scroll(proxy, to: state.anchorVerse) }
                .onChange(of: state.actionBarVisible) { _, on in if on { reveal(proxy) } }
                .onChange(of: state.actionBarVerse) { _, _ in if state.actionBarVisible { reveal(proxy) } }
                .onChange(of: topID) { _, new in
                    guard tracking, let new else { return }
                    state.scrolled(toVerse: new < 0 ? (nums.first ?? 1) : new)
                }
            }
        }
    }

    /// La barra inferior reduce el área visible: desplaza lo mínimo para que la fila siga a la vista.
    private func reveal(_ proxy: ScrollViewProxy) {
        let verse = state.actionBarVerse
        tracking = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            if numbers(glossStyle ? groups() : []).contains(verse) { proxy.scrollTo(verse) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { tracking = true }
        }
    }

    private func scroll(_ proxy: ScrollViewProxy, to verse: Int) {
        tracking = false
        DispatchQueue.main.async {
            let rows = numbers(glossStyle ? groups() : [])
            let target = rows.first { $0 >= verse }
            let id = (target == nil || target == rows.first) ? -1 : target!
            proxy.scrollTo(id, anchor: .top)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { proxy.scrollTo(id, anchor: .top) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { tracking = true }
        }
    }
}

/// Color de acento (solo texto) de la versión `i` de la lista de columnas.
func versionAccent(_ i: Int, _ theme: Theme) -> Color { theme.palette.versionAccent[i % 3] }

func languageName(_ code: String) -> String {
    switch code { case "zh": "中文"; case "es": "Español"; case "en": "English"; default: code.uppercased() }
}

/// Cabeceras de columna fijas (fuera del ScrollView): la identidad de la versión vive solo aquí.
private struct ColumnHeaders: View {
    @Environment(AppState.self) private var state
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: ParallelMetrics.columnGap) {
            ForEach(Array(state.parallelColumns.enumerated()), id: \.element.id) { i, t in
                HStack(spacing: 6) {
                    Text(t.id).font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(versionAccent(i, theme))
                        .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                    Text(languageName(t.language)).font(.system(size: 11))
                        .lineLimit(1).truncationMode(.tail)
                        .foregroundStyle(theme.palette.textSecondary)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 6).padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .columnSeparator(show: i > 0, theme: theme)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Columna \(t.name), \(languageName(t.language))")
                .accessibilityAddTraits(.isHeader)
            }
        }
        .padding(.horizontal, 24).padding(.vertical, 6)
        .background(theme.palette.background)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.palette.border).frame(height: 1) }
    }
}

extension View {
    /// Línea vertical fina en el borde izquierdo (centrada en el hueco entre columnas).
    func columnSeparator(show: Bool, theme: Theme) -> some View {
        overlay(alignment: .leading) {
            if show { Rectangle().fill(theme.palette.border).frame(width: 1).offset(x: -ParallelMetrics.columnGap / 2 - 0.5) }
        }
    }
}

private struct ParallelRowView: View {
    @Environment(AppState.self) private var state
    @Environment(\.theme) private var theme
    let row: ParallelRow

    var body: some View {
        let selected = state.selectedVerses.contains(row.number)
        let cols = state.parallelColumns
        HStack(alignment: .top, spacing: ParallelMetrics.columnGap) {
            ForEach(Array(row.cells.enumerated()), id: \.offset) { i, cell in
                ParallelCellView(cell: cell, column: cols[safe: i], row: row.number, selected: selected)
                    .columnSeparator(show: i > 0, theme: theme)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, theme.verseGap + theme.pt * 0.25)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.palette.border.opacity(0.7)).frame(height: 1) }
        .contentShape(Rectangle())
        .onTapGesture {
            let m = NSEvent.modifierFlags
            state.clickVerse(row.number, shift: m.contains(.shift), command: m.contains(.command))
        }
        .contextMenu { VerseMenuItems(scope: state.scope(forContextVerse: row.number)) }
    }
}

/// Celda de columna: texto sobre el fondo normal; la selección y el resaltado van solo sobre el texto.
private struct ParallelCellView: View {
    @Environment(\.theme) private var theme
    @Environment(AppSettings.self) private var settings
    @Environment(AppState.self) private var state
    let cell: ParallelCell
    let column: Translation?
    let row: Int
    let selected: Bool

    private var latin: Bool { (column?.language ?? "es") != "zh" }
    private var name: String { column?.name ?? column?.id ?? "" }
    private var highlight: TextHighlight {
        column.map { state.highlight(for: $0.id) } ?? TextHighlight(terms: state.searchTerms, flash: state.flashVerses, flashAlpha: state.flashAlpha)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch cell {
            case .verse(let v):
                if settings.showHeadings {
                    ForEach(Array(v.headings.enumerated()), id: \.offset) { i, h in
                        Text(h).font(theme.headingFont).foregroundStyle(theme.palette.heading)
                            .padding(.top, i == 0 ? theme.pt * 0.2 : theme.pt * 0.1)
                            .padding(.bottom, theme.pt * 0.3)
                            .accessibilityAddTraits(.isHeader)
                    }
                }
                Text(VerseText.attributed(verses: [v], theme: theme, latin: latin, selected: selected ? [v.number] : [], links: false,
                                           hl: highlight))
                    .lineSpacing(theme.lineSpacing(latin: latin))
                    .tracking(latin ? 0 : theme.pt * 0.02)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .environment(\.openURL, OpenURLAction { url in
                        if let id = NoteLink.parse(url) { state.openNoteIcon(id: id); return .handled }
                        guard url.scheme == StrongLink.scheme else { return .systemAction }
                        state.openStrong(link: url); return .handled
                    })
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(name). Versículo \(v.label). \(v.text)")
            case .covered(let v):
                Text("\u{2191} (\(v.label))")
                    .font(.system(size: theme.pt * 0.85)).foregroundStyle(theme.palette.textMuted)
                    .accessibilityLabel("\(name). Versículo \(row) incluido en el versículo \(v.label)")
            case .missing:
                Text("\u{2014}")
                    .font(.system(size: theme.pt)).foregroundStyle(theme.palette.textMuted)
                    .accessibilityLabel("Versículo \(row) no existe en \(name)")
            }
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}
