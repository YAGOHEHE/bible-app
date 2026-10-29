import BibliaCore
import SwiftUI

/// S08: ajustes. Todo se aplica en vivo.
struct SettingsView: View {
    @Environment(AppState.self) private var state
    @Environment(AppSettings.self) private var settings
    @Environment(\.theme) private var theme

    var body: some View {
        @Bindable var s = settings
        Form {
            Section("Lectura") {
                Picker("Versión predeterminada", selection: Binding(
                    get: { s.defaultTranslation },
                    set: { s.defaultTranslation = $0; state.setTranslation($0) })) {
                    ForEach(state.translations) { Text("\($0.name) (\($0.id))").tag($0.id) }
                }
                LabeledContent("Tamaño de texto") {
                    HStack {
                        Slider(value: $s.fontScale, in: FontScale.min...FontScale.max, step: FontScale.step)
                            .accessibilityLabel("Tamaño de lectura")
                            .accessibilityValue("\(Int((s.fontScale * 100).rounded())) por ciento")
                        Text("\(Int((s.fontScale * 100).rounded())) %").monospacedDigit().frame(width: 52, alignment: .trailing)
                    }
                }
                Picker("Diseño", selection: $s.verseLayout) {
                    ForEach(VerseLayout.allCases) { Text($0.label).tag($0) }
                }
                Toggle("Mostrar títulos de sección", isOn: $s.showHeadings)
            }
            Section("Versiones (vista paralela)") {
                VersionEmptyNote()
                ForEach(state.versionSet.order.compactMap { id in state.translations.first { $0.id == id } }) { t in
                    VersionRow(t: t, showMoveButtons: true)
                }
                Button("Importar módulo…") {}.disabled(true).help("Próximamente")
            }
            Section("Apariencia") {
                Picker("Tema", selection: $s.themeChoice) {
                    ForEach(ThemeChoice.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                Text("Sepia usa fondo de papel y apariencia clara en toda la ventana.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Vista previa") {
                preview
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(VerseText.attributed(verses: [DisplayVerse(number: 16, endNumber: 16, text: "神爱世人，甚至将他的独生子赐给他们。", headings: [])],
                                      theme: theme, latin: false, selected: []))
                .lineSpacing(theme.lineSpacing(latin: false))
            Text(VerseText.attributed(verses: [DisplayVerse(number: 16, endNumber: 16, text: "Porque de tal manera amó Dios al mundo.", headings: [])],
                                      theme: theme, latin: true, selected: []))
                .lineSpacing(theme.lineSpacing(latin: true))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(theme.palette.background, in: RoundedRectangle(cornerRadius: 8))
        .clipped()
    }
}
