import Foundation

/// Fechas de la interfaz. La interfaz de Biblia está en español, así que las fechas se muestran siempre en español
/// (como los títulos «Hoy / Ayer / lunes, 5 de octubre» del historial), sin depender de la región del sistema.
enum DateText {
    static let locale = Locale(identifier: "es")

    static func date(_ t: Double, calendar: Calendar = .current) -> String { string(t, "dMMMy", calendar) }
    static func dateTime(_ t: Double, calendar: Calendar = .current) -> String { string(t, "dMMMyjmm", calendar) }
    static func time(_ t: Double, calendar: Calendar = .current) -> String { string(t, "jmm", calendar) }

    private static func string(_ t: Double, _ template: String, _ calendar: Calendar) -> String {
        let f = DateFormatter()
        f.locale = locale
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.setLocalizedDateFormatFromTemplate(template)
        return f.string(from: Date(timeIntervalSince1970: t))
    }
}
