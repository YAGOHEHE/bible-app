import BibliaCore
import SwiftUI

/// Ventana "Acerca de Biblia": versión, fuentes y licencias (atribución requerida).
struct AboutView: View {
    @Environment(AppState.self) private var state

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    if let icon = NSApp.applicationIconImage { Image(nsImage: icon).resizable().frame(width: 64, height: 64) }
                    VStack(alignment: .leading) {
                        Text("Biblia").font(.title.bold())
                        Text("Versión \(version)").foregroundStyle(.secondary)
                    }
                }
                Text("Lector bíblico independiente, gratuito y sin relación con ninguna otra aplicación bíblica. Todos los textos incluidos son de dominio público.")
                    .fixedSize(horizontal: false, vertical: true)

                Text("Versiones de la Biblia").font(.headline)
                ForEach(state.translations) { t in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t.name).fontWeight(.semibold)
                        Text("Licencia: \(t.license ?? "—")").font(.callout).foregroundStyle(.secondary)
                        if let s = t.sourceURL, let url = URL(string: s) { Link(s, destination: url).font(.callout) }
                    }
                }
                Text("Textos obtenidos de eBible.org mediante la API HelloAO Free Use Bible. KJV con números Strong: eBible.org / Crosswire Bible Society.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)

                Text("Versiones adicionales: 和合本 tradicional (cmn_cuv), Berean Standard Bible (dominio público desde el 30 de abril de 2023, https://berean.bible/terms.htm), World English Bible y Santa Biblia libre para el mundo, todas de dominio público.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)

                Text("Referencias cruzadas").font(.headline)
                Text("Referencias cruzadas: OpenBible.info, bajo licencia Creative Commons Atribución (CC BY 4.0), https://www.openbible.info/labs/cross-references/. Derivadas principalmente del Treasury of Scripture Knowledge (dominio público).")
                    .fixedSize(horizontal: false, vertical: true)

                Text("Léxico Strong").font(.headline)
                Text("Diccionarios hebreo y griego de Strong (dominio público) a través de OpenScriptures (https://github.com/openscriptures/strongs).")
                    .fixedSize(horizontal: false, vertical: true)

                Text("Estructura del texto").font(.headline)
                Text("La estructura de párrafos y poesía de la RV1909 se adapta de la Berean Standard Bible (dominio público, https://berean.bible/terms.htm).")
                    .fixedSize(horizontal: false, vertical: true)

                Text("Tipografía").font(.headline)
                Text("Texto latino en Literata, © 2017 The Literata Project Authors (https://github.com/googlefonts/literata), bajo la licencia SIL Open Font License 1.1 (https://openfontlicense.org). El texto chino usa Songti SC del sistema.")
                    .fixedSize(horizontal: false, vertical: true)

                Text("Software").font(.headline)
                Text("Usa GRDB.swift (licencia MIT, Gwendal Roué).")
                Text("KJV: en el Reino Unido la Corona restringe la impresión de ejemplares en papel; no afecta al uso digital en otros países.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
        }
        .frame(width: 520, height: 560)
    }
}
