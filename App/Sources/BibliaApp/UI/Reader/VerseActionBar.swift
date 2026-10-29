import SwiftUI

/// Barra de acciones flotante (popover) sobre los versículos seleccionados.
struct VerseActionBar: View {
    @Environment(AppState.self) private var state
    @Environment(\.theme) private var theme
    /// `nil` = la selección actual.
    var scope: Set<Int>?

    var body: some View {
        let ctx = state.actionContext(scope: scope)
        let actions = VerseActions.visible(ctx).filter { $0 != .highlight }
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 2) {
                ForEach(actions) { a in
                    ActionButton(action: a, scope: scope)
                }
            }
            Divider().overlay(theme.palette.border)
            HStack(spacing: 8) {
                Image(systemName: "highlighter").font(.system(size: 13))
                    .foregroundStyle(theme.palette.textSecondary).accessibilityHidden(true)
                ForEach(HighlightColor.allCases) { c in
                    Swatch(color: c, scope: scope)
                }
                Spacer(minLength: 4)
                Button("Quitar") { state.removeHighlightSelection(scope: scope) }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(state.selectionHasHighlight(scope: scope) ? theme.palette.accent : theme.palette.textMuted)
                    .disabled(!state.selectionHasHighlight(scope: scope) || !ctx.annotationsAvailable)
                    .help("Quitar resaltado")
                    .accessibilityLabel("Quitar resaltado")
            }
        }
        .padding(10)
        .frame(minWidth: 360)
        .background(theme.palette.surface)
        .onExitCommand { state.actionBarVisible = false }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Acciones del versículo")
    }
}

private struct ActionButton: View {
    @Environment(AppState.self) private var state
    @Environment(\.theme) private var theme
    let action: VerseAction
    let scope: Set<Int>?

    var body: some View {
        let enabled = VerseActions.isEnabled(action, state.actionContext(scope: scope))
        let filled = action == .bookmark && state.selectionBookmarked(scope: scope)
        let count = action == .crossRefs ? state.selectionCrossRefCount(scope: scope) : 0
        Button { state.perform(action, scope: scope) } label: {
            VStack(spacing: 3) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: filled ? "bookmark.fill" : action.symbol)
                        .font(.system(size: 16))
                        .foregroundStyle(filled ? theme.palette.bookmarkMarker : theme.palette.textPrimary)
                        .frame(width: 26, height: 22)
                    if count > 0 {
                        Text(count > 99 ? "99+" : "\(count)")
                            .font(.system(size: 9, weight: .bold)).monospacedDigit()
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(theme.palette.accent, in: Capsule())
                            .foregroundStyle(theme.palette.onAccent)
                            .offset(x: 8, y: -3)
                            .accessibilityHidden(true)
                    }
                }
                Text(label).font(.system(size: 10)).lineLimit(1)
                    .foregroundStyle(theme.palette.textSecondary)
            }
            .frame(width: 58, height: 46)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .help(help)
        .accessibilityLabel(action == .crossRefs && count > 0 ? "Referencias, \(count)" : label)
    }

    private var label: String {
        switch action {
        case .copyReference: "Con ref."
        case .bookmark: state.selectionBookmarked(scope: scope) ? "Quitar" : "Marcador"
        default: action.title
        }
    }
    private var help: String {
        switch action {
        case .copy: "Copiar (⌘C)"
        case .copyReference: "Copiar con referencia (⌥⌘C)"
        case .note: "Anotar (⌥⌘N)"
        case .bookmark: "Marcador (⌘D)"
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
                .frame(width: 20, height: 20)
                .overlay(Circle().strokeBorder(current ? theme.palette.textPrimary : theme.palette.borderInput,
                                               lineWidth: current ? 2 : 1))
                .overlay { if current { Image(systemName: "checkmark").font(.system(size: 9, weight: .bold))
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
