import SwiftUI

/// Inspector con pestañas: Strong · Nota · Referencias.
struct InspectorView: View {
    @Environment(AppState.self) private var state
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            Picker("Pestaña", selection: Binding(get: { state.inspectorTab }, set: { state.inspectorTab = $0 })) {
                ForEach(InspectorTab.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden()
            .padding(10)
            switch state.inspectorTab {
            case .strong: StrongPanel()
            case .note: NoteTab()
            case .refs: RefsTab()
            }
        }
        .background(theme.palette.surface)
        .onChange(of: state.inspectorTab) { old, _ in if old == .note { state.noteEditor.flush() } }
    }
}
