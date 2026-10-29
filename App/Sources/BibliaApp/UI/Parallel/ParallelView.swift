import SwiftUI
import AppKit

/// S03: vista paralela. Una sola lista de filas por versículo con N celdas (desplazamiento sincronizado).
struct ParallelView: View {
    @Environment(AppState.self) private var state
    @Environment(\.theme) private var theme

    var body: some View {
        Group {
            if state.parallelColumns.count < 2 {
                ContentUnavailableView {
                    Label("Activa otra versión para comparar", systemImage: "rectangle.split.2x1")
                } description: {
                    Text("La vista paralela necesita al menos dos versiones activas. Actívalas en el gestor de versiones.")
                } actions: {
                    Button("Abrir gestor de versiones") { state.showVersions = true }
                }
                .foregroundStyle(theme.palette.textSecondary)
            } else if state.parallelRows.isEmpty {
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
                .id(state.chapterKey + state.parallelColumns.map(\.id).joined())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.palette.background)
        .overlay(alignment: .bottom) { ToastView() }
        .overlay(alignment: .topTrailing) { SearchTermsChip() }
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

    var body: some View {
        VStack(spacing: 0) {
            ColumnHeaders(stacked: stacked)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        Text("\(state.bookName(state.book)) \(state.chapter)")
                            .font(theme.chapterTitleFont)
                            .foregroundStyle(theme.palette.textPrimary)
                            .accessibilityAddTraits(.isHeader)
                            .padding(.bottom, theme.pt * 0.6)
                            .id(-1)
                        ForEach(state.parallelRows) { row in
                            ParallelRowView(row: row, stacked: stacked).id(row.number)
                        }
                    }
                    .scrollTargetLayout()
                    .padding(.horizontal, 24)
                    .padding(.vertical, 20)
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
                .onChange(of: topID) { _, new in
                    guard tracking, let new else { return }
                    state.scrolled(toVerse: new < 0 ? (state.parallelRows.first?.number ?? 1) : new)
                }
            }
        }
    }

    private func scroll(_ proxy: ScrollViewProxy, to verse: Int) {
        tracking = false
        DispatchQueue.main.async {
            let rows = state.parallelRows
            let target = rows.first { $0.number >= verse }?.number
            let id = (target == nil || target == rows.first?.number) ? -1 : target!
            proxy.scrollTo(id, anchor: .top)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { proxy.scrollTo(id, anchor: .top) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { tracking = true }
        }
    }
}

func parallelTint(_ i: Int, _ theme: Theme) -> Color { theme.palette.parallel[i % 3] }
func parallelAccent(_ i: Int, _ theme: Theme) -> Color {
    [theme.palette.accent, theme.palette.textMuted, theme.palette.strongUnderline][i % 3]
}

/// Cabeceras de columna fijas (fuera del ScrollView). En modo apilado, leyenda de colores.
private struct ColumnHeaders: View {
    @Environment(AppState.self) private var state
    @Environment(\.theme) private var theme
    let stacked: Bool

    var body: some View {
        HStack(spacing: ParallelMetrics.columnGap) {
            ForEach(Array(state.parallelColumns.enumerated()), id: \.element.id) { i, t in
                HStack(spacing: 6) {
                    Text(t.id).font(.system(size: 13, weight: .semibold))
                        .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                    if !stacked {
                        Text(languageName(t.language)).font(.system(size: 11))
                            .lineLimit(1).truncationMode(.tail)
                            .foregroundStyle(theme.palette.textSecondary)
                        Text(t.name).font(.system(size: 11)).lineLimit(1).truncationMode(.tail)
                            .foregroundStyle(theme.palette.textSecondary)
                    }
                    Spacer(minLength: 0)
                }
                .foregroundStyle(theme.palette.textPrimary)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(parallelTint(i, theme), in: RoundedRectangle(cornerRadius: 6))
                .overlay(alignment: .leading) {
                    Rectangle().fill(parallelAccent(i, theme)).frame(width: 3).clipShape(RoundedRectangle(cornerRadius: 1.5))
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Columna \(t.name), \(languageName(t.language))")
                .accessibilityAddTraits(.isHeader)
            }
        }
        .padding(.horizontal, 24).padding(.vertical, 8)
        .background(theme.palette.background)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.palette.border).frame(height: 1) }
    }
}

func languageName(_ code: String) -> String {
    switch code { case "zh": "中文"; case "es": "Español"; case "en": "English"; default: code.uppercased() }
}

private struct ParallelRowView: View {
    @Environment(AppState.self) private var state
    @Environment(\.theme) private var theme
    let row: ParallelRow
    let stacked: Bool

    var body: some View {
        let selected = state.selectedVerses.contains(row.number)
        let flash = state.flashVerses.contains(row.number) ? state.flashAlpha : 0
        let cols = state.parallelColumns
        Group {
            if stacked {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(row.cells.enumerated()), id: \.offset) { i, cell in
                        ParallelCellView(cell: cell, index: i, column: cols[safe: i], row: row.number,
                                         selected: selected, showTag: true, flash: flash)
                    }
                }
            } else {
                HStack(alignment: .top, spacing: ParallelMetrics.columnGap) {
                    ForEach(Array(row.cells.enumerated()), id: \.offset) { i, cell in
                        ParallelCellView(cell: cell, index: i, column: cols[safe: i], row: row.number,
                                         selected: selected, showTag: false, stretch: true, flash: flash)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, theme.verseGap + (stacked ? theme.pt * 0.3 : 0))
        .contentShape(Rectangle())
        .onTapGesture {
            let m = NSEvent.modifierFlags
            state.clickVerse(row.number, shift: m.contains(.shift), command: m.contains(.command))
        }
    }
}

private struct ParallelCellView: View {
    @Environment(\.theme) private var theme
    @Environment(AppSettings.self) private var settings
    let cell: ParallelCell
    let index: Int
    let column: Translation?
    let row: Int
    let selected: Bool
    let showTag: Bool
    var stretch = false
    var flash: Double = 0
    @Environment(AppState.self) private var state

    private var latin: Bool { (column?.language ?? "es") != "zh" }
    private var name: String { column?.name ?? column?.id ?? "" }
    private var parallelHighlight: TextHighlight {
        var h = column.map { state.highlight(for: $0.id) } ?? TextHighlight(terms: state.searchTerms)
        h.flash = []; h.flashAlpha = 0   // la fila ya se destaca por fondo
        return h
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showTag, let c = column {
                Text(c.id).font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(theme.palette.textSecondary).padding(.bottom, 2)
            }
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
                Text(VerseText.attributed(verses: [v], theme: theme, latin: latin, selected: [], links: false,
                                           hl: parallelHighlight))
                    .lineSpacing(theme.lineSpacing(latin: latin))
                    .tracking(latin ? 0 : theme.pt * 0.02)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .environment(\.openURL, OpenURLAction { url in
                        guard url.scheme == StrongLink.scheme else { return .systemAction }
                        state.openStrong(link: url); return .handled
                    })
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(name). Versículo \(v.label). \(v.text)")
            case .covered(let v):
                Text("↑ (\(v.label))")
                    .font(.system(size: theme.pt * 0.85)).foregroundStyle(theme.palette.textMuted)
                    .accessibilityLabel("\(name). Versículo \(row) incluido en el versículo \(v.label)")
            case .missing:
                Text("—")
                    .font(.system(size: theme.pt)).foregroundStyle(theme.palette.textMuted)
                    .accessibilityLabel("Versículo \(row) no existe en \(name)")
            }
        }
        .padding(.leading, 11).padding(.trailing, 8).padding(.vertical, 6)
        .frame(maxWidth: .infinity, maxHeight: stretch ? .infinity : nil, alignment: .topLeading)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 6).fill(selected ? theme.palette.selection : parallelTint(index, theme))
                RoundedRectangle(cornerRadius: 6).fill(theme.palette.selection.opacity(flash))
            }
        }
        .overlay(alignment: .leading) {
            Rectangle().fill(parallelAccent(index, theme)).frame(width: 3)
                .clipShape(RoundedRectangle(cornerRadius: 1.5))
        }
        .overlay {
            if case .missing = cell {
                RoundedRectangle(cornerRadius: 6).strokeBorder(theme.palette.border, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
        }
    }
}
