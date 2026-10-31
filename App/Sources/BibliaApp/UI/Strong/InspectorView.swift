import BibliaCore
import SwiftUI

/// Inspector con pestañas de texto: Strong · Nota · Referencias (n). La activa lleva una línea de 2 pt en accent.
struct InspectorView: View {
    @Environment(AppState.self) private var state
    @Environment(\.theme) private var theme
    @State private var refsCount = 0

    private struct RefsKey: Equatable { var r: ClosedRange<Int>?; var b: Int; var c: Int }

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            switch state.inspectorTab {
            case .strong: StrongPanel()
            case .note: NoteTab()
            case .refs: RefsTab()
            }
        }
        .background(theme.palette.surface)
        .onChange(of: state.inspectorTab) { old, _ in if old == .note { state.noteEditor.flush() } }
        .task(id: RefsKey(r: state.refsTarget, b: state.refsBook, c: state.refsChapter)) { refsCount = state.crossRefs().count }
    }

    private var tabBar: some View {
        HStack(spacing: 18) {
            ForEach(InspectorTab.allCases) { tab in
                let active = state.inspectorTab == tab
                Button { state.inspectorTab = tab } label: {
                    HStack(spacing: 4) {
                        Text(tab.label)
                        if let n = InspectorTabModel.badge(tab, refsCount: refsCount) {
                            Text("\(n)").font(theme.uiFont(size: 11)).monospacedDigit()
                                .foregroundStyle(theme.palette.textMuted)
                        }
                    }
                    .font(theme.uiFont(size: 13, weight: active ? .semibold : .regular))
                    .foregroundStyle(active ? theme.palette.textPrimary : theme.palette.textSecondary)
                    .padding(.vertical, 9)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(active ? theme.palette.accent : Color.clear).frame(height: 2)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(InspectorTabModel.title(tab, refsCount: refsCount))
                .accessibilityAddTraits(active ? [.isSelected, .isButton] : .isButton)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.palette.border).frame(height: 1) }
    }
}
