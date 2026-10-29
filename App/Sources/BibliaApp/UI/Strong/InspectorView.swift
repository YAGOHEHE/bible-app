import SwiftUI

/// Inspector con pestañas: Strong · Nota · Referencias. Nota y Referencias son marcadores de posición
/// hasta la tarea 5 (editor de notas y lista de referencias cruzadas).
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
            case .note: placeholder("Nota", range: state.noteTarget, symbol: "square.and.pencil")
            case .refs: placeholder("Referencias", range: state.refsTarget, symbol: "arrow.triangle.branch")
            }
        }
        .background(theme.palette.surface)
    }

    private func placeholder(_ title: String, range: ClosedRange<Int>?, symbol: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 28)).foregroundStyle(theme.palette.textMuted)
            Text(title).font(.headline).foregroundStyle(theme.palette.textPrimary)
            Text(range.map { r in
                "\(state.bookName(state.book)) \(state.chapter):" + (r.lowerBound == r.upperBound ? "\(r.lowerBound)" : "\(r.lowerBound)–\(r.upperBound)")
            } ?? "Selecciona un versículo")
                .font(.callout).foregroundStyle(theme.palette.textSecondary)
            Text("Próximamente").font(.caption).foregroundStyle(theme.palette.textMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}
