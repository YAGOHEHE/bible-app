import BibliaCore
import SwiftUI

/// Métricas de la tarjeta «Códice» (puras, probadas en `CodiceActionBarTests`).
enum VerseBarMetrics {
    static let buttonWidth: CGFloat = 64, buttonHeight: CGFloat = 56
    static let compactWidth: CGFloat = 34, compactHeight: CGFloat = 40
    static let spacing: CGFloat = 2
    /// Margen exterior de la tarjeta respecto al panel y relleno interior.
    static let outerMargin: CGFloat = 12, innerPadding: CGFloat = 14
    static let swatch: CGFloat = 24
    static let corner: CGFloat = 14

    static func rowWidth(count: Int, compact: Bool) -> CGFloat {
        let n = CGFloat(max(0, count))
        return n * (compact ? compactWidth : buttonWidth) + max(0, n - 1) * spacing
    }
    /// `width` = ancho disponible del panel de lectura. Compacto = solo iconos (sigue cabiendo en ~300 pt).
    /// Se reutilizan los casos de `ActionBarLayout`: `.oneRow` = botones con etiqueta, `.compact` = solo iconos.
    static func layout(width: CGFloat, actionCount: Int) -> ActionBarLayout {
        rowWidth(count: actionCount, compact: false) + 2 * (innerPadding + outerMargin) <= width ? .oneRow : .compact
    }
}

/// Barra de acciones anclada abajo del panel de lectura (dentro de la columna de detalle, así nunca
/// invade la barra lateral ni el inspector). Se inserta como `safeAreaInset`: el texto se desplaza
/// y el versículo seleccionado no queda tapado. Tarjeta «Códice»: cabecera, fila de acciones, resaltado.
struct VerseActionBar: View {
    @Environment(AppState.self) private var state
    @Environment(\.theme) private var theme
    /// `nil` = la selección actual.
    var scope: Set<Int>?
    @State private var width: CGFloat = 800

    private var referenceText: String {
        let verses = state.targetVerses(scope)
        let r = VerseActions.range(of: verses)
        return RefLabel.text(bookName: state.bookName(state.book), chapter: state.chapter, from: r?.lowerBound, to: r?.upperBound)
    }

    var body: some View {
        let ctx = state.actionContext(scope: scope)
        let actions = VerseActions.visible(ctx).filter { $0 != .highlight }
        let compact = VerseBarMetrics.layout(width: width, actionCount: actions.count) == .compact
        let hasHighlight = state.selectionHasHighlight(scope: scope)
        let removeEnabled = hasHighlight && ctx.annotationsAvailable
        let swatchRow = { (showLabel: Bool) in
            HStack(spacing: 8) {
                if showLabel {
                    Text("Resaltar").font(theme.uiFont(size: 12, weight: .medium))
                        .foregroundStyle(theme.palette.textSecondary).fixedSize()
                        .padding(.trailing, 2)
                }
                ForEach(HighlightColor.allCases) { c in Swatch(color: c, scope: scope) }
                Spacer(minLength: 8)
                Button("Quitar") { state.removeHighlightSelection(scope: scope) }
                    .buttonStyle(.plain)
                    .font(theme.uiFont(size: 12, weight: .semibold))
                    .foregroundStyle(theme.palette.accent.opacity(removeEnabled ? 1 : 0.4))
                    .disabled(!removeEnabled)
                    .help("Quitar resaltado")
                    .accessibilityLabel("Quitar resaltado")
            }
        }
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(referenceText).font(theme.uiFont(size: 13, weight: .semibold))
                    .foregroundStyle(theme.palette.textPrimary).lineLimit(1)
                Spacer(minLength: 8)
                Text(state.translationId).font(theme.uiFont(size: 12, weight: .medium))
                    .foregroundStyle(theme.palette.textMuted)
                Button { state.actionBarVisible = false } label: {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(theme.palette.textMuted).frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Cerrar barra (Esc)")
                .accessibilityLabel("Cerrar barra de acciones")
            }
            HStack(spacing: VerseBarMetrics.spacing) {
                ForEach(actions) { a in ActionButton(action: a, scope: scope, compact: compact) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Divider().overlay(theme.palette.border)
            ViewThatFits(in: .horizontal) {
                swatchRow(true)
                swatchRow(false)
            }
        }
        .padding(.horizontal, VerseBarMetrics.innerPadding).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: VerseBarMetrics.corner).fill(theme.palette.surface))
        .overlay(RoundedRectangle(cornerRadius: VerseBarMetrics.corner).strokeBorder(theme.palette.border, lineWidth: 1))
        .shadow(color: .black.opacity(0.16), radius: 32, x: 0, y: 12)
        .padding(.horizontal, VerseBarMetrics.outerMargin).padding(.top, 6).padding(.bottom, 12)
        .frame(maxWidth: .infinity)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .onExitCommand { state.actionBarVisible = false }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Acciones del versículo")
    }
}

/// Hueco inferior con la barra, solo mientras hay selección y la barra está abierta.
struct ActionBarInset: ViewModifier {
    @Environment(AppState.self) private var state
    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom, spacing: 0) {
            if state.actionBarVisible && !state.selectedVerses.isEmpty { VerseActionBar(scope: nil) }
        }
    }
}

extension View {
    func verseActionBarDock() -> some View { modifier(ActionBarInset()) }
}

private struct ActionButton: View {
    @Environment(AppState.self) private var state
    @Environment(\.theme) private var theme
    let action: VerseAction
    let scope: Set<Int>?
    var compact = false

    var body: some View {
        let enabled = VerseActions.isEnabled(action, state.actionContext(scope: scope))
        let filled = action == .bookmark && state.selectionBookmarked(scope: scope)
        let count = action == .crossRefs ? state.selectionCrossRefCount(scope: scope) : 0
        Button { state.perform(action, scope: scope) } label: {
            VStack(spacing: 4) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: filled ? "bookmark.fill" : action.symbol)
                        .font(.system(size: 17))
                        .foregroundStyle(filled ? theme.palette.bookmarkMarker : theme.palette.textPrimary)
                        .frame(width: 26, height: 22)
                    if count > 0 {
                        Text(count > 99 ? "99+" : "\(count)")
                            .font(.system(size: 9, weight: .bold)).monospacedDigit()
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(theme.palette.accent, in: Capsule())
                            .foregroundStyle(theme.palette.onAccent)
                            .offset(x: 9, y: -4)
                            .accessibilityHidden(true)
                    }
                }
                if !compact {
                    Text(label).font(theme.uiFont(size: 11)).lineLimit(1).minimumScaleFactor(0.8)
                        .foregroundStyle(theme.palette.textSecondary)
                }
            }
            .frame(width: compact ? VerseBarMetrics.compactWidth : VerseBarMetrics.buttonWidth,
                   height: compact ? VerseBarMetrics.compactHeight : VerseBarMetrics.buttonHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .help(help)
        .accessibilityLabel(a11y(count: count))
    }

    /// Etiqueta visible (corta).
    private var label: String {
        switch action {
        case .copy: "Copiar"
        case .copyReference: "Citar"
        case .note: "Nota"
        case .bookmark: state.selectionBookmarked(scope: scope) ? "Desmarcar" : "Marcar"
        default: action.title
        }
    }
    private func a11y(count: Int) -> String {
        switch action {
        case .crossRefs: count > 0 ? "Referencias, \(count)" : "Referencias"
        case .copyReference: "Citar, copiar con referencia"
        case .note: "Anotar"
        case .bookmark: state.selectionBookmarked(scope: scope) ? "Quitar marcador" : "Marcador"
        default: action.title
        }
    }
    private var help: String {
        switch action {
        case .copy: "Copiar (⌘C)"
        case .copyReference: "Citar: copiar con referencia (⌥⌘C)"
        case .note: "Anotar (⌥⌘N)"
        case .bookmark: "Marcador (⌘D)"
        case .crossRefs: "Referencias cruzadas"
        case .compare: "Comparar versiones"
        case .strong: "Abrir en modo Strong"
        default: action.title
        }
    }
}

private struct Swatch: View {
    @Environment(AppState.self) private var state
    @Environment(\.theme) private var theme
    let color: HighlightColor
    let scope: Set<Int>?

    var body: some View {
        let current = state.highlightColor(of: state.targetVerses(scope)) == color
        Button { state.highlightSelection(color, scope: scope) } label: {
            Circle().fill(theme.palette.highlight[color] ?? theme.palette.surface)
                .frame(width: VerseBarMetrics.swatch, height: VerseBarMetrics.swatch)
                .overlay(Circle().strokeBorder(current ? theme.palette.textPrimary : theme.palette.borderInput,
                                               lineWidth: current ? 2 : 1))
                .overlay { if current { Image(systemName: "checkmark").font(.system(size: 10, weight: .bold))
                    .foregroundStyle(theme.palette.textPrimary) } }
        }
        .buttonStyle(.plain)
        .disabled(state.annotations == nil)
        .help("Resaltar en \(color.displayName.lowercased())")
        .accessibilityLabel("Resaltar en \(color.displayName.lowercased())")
    }
}

/// Elementos del menú contextual (clic derecho en un versículo o fila).
struct VerseMenuItems: View {
    @Environment(AppState.self) private var state
    /// Alcance explícito (versículo pulsado fuera de la selección); `nil` = selección.
    var scope: Set<Int>?

    var body: some View {
        let ctx = state.actionContext(scope: scope)
        let actions = VerseActions.visible(ctx)
        ForEach(actions.filter { $0 == .copy || $0 == .copyReference }) { a in
            Button(a.title) { state.perform(a, scope: scope) }
                .disabled(!VerseActions.isEnabled(a, ctx))
        }
        Divider()
        Menu("Resaltar con") {
            ForEach(HighlightColor.allCases) { c in
                Button(c.displayName) { state.highlightSelection(c, scope: scope) }
            }
            Divider()
            Button("Quitar resaltado") { state.removeHighlightSelection(scope: scope) }
                .disabled(!state.selectionHasHighlight(scope: scope))
        }
        .disabled(!VerseActions.isEnabled(.highlight, ctx))
        ForEach(actions.filter { $0 != .copy && $0 != .copyReference && $0 != .highlight }) { a in
            Button(a == .bookmark && state.selectionBookmarked(scope: scope) ? "Quitar marcador" : a.title) {
                state.perform(a, scope: scope)
            }
            .disabled(!VerseActions.isEnabled(a, ctx))
        }
    }
}
