import Foundation
import CoreText

/// Registra las fuentes incluidas (Literata, licencia OFL: `Resources/Fonts/OFL.txt`) en el ámbito del proceso.
/// Sin `Bundle.module`: usa el mismo paquete de recursos que `BibleDatabase`. Compatible con macOS 10.13.
public enum FontRegistry {
    public static let literataFiles = ["Literata-Regular", "Literata-Medium", "Literata-SemiBold", "Literata-Italic"]

    /// Carpeta `Fonts` del paquete de recursos (o de `App/Resources` en desarrollo).
    public static func fontsDirectory() -> URL? {
        let fm = FileManager.default
        var cands: [URL] = []
        if let b = BibleDatabase.resourceBundleURL() {
            cands.append(b.appendingPathComponent("Resources/Fonts"))
            cands.append(b.appendingPathComponent("Fonts"))
        }
        cands.append(URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/Fonts"))
        return cands.first { fm.fileExists(atPath: $0.appendingPathComponent("Literata-Regular.ttf").path) }
    }

    private static var registered: Int?

    /// Registra los TTF una sola vez; devuelve cuántos quedaron registrados (0 = usar la serif del sistema).
    @discardableResult
    public static func registerBundledFonts() -> Int {
        if let r = registered { return r }
        var n = 0
        if let dir = fontsDirectory() {
            for f in literataFiles {
                let url = dir.appendingPathComponent(f + ".ttf") as CFURL
                var err: Unmanaged<CFError>?
                if CTFontManagerRegisterFontsForURL(url, .process, &err) { n += 1 }
                else if let e = err?.takeRetainedValue(), CFErrorGetCode(e) == 105 { n += 1 } // ya registrada
            }
        }
        registered = n
        return n
    }

    /// `true` si Literata está disponible para dibujar (registrada con éxito).
    public static var literataAvailable: Bool {
        registerBundledFonts()
        // CTFontCreateWithName devuelve una fuente de sustitución si el nombre no existe: se comprueba la familia.
        let f = CTFontCreateWithName("Literata-Regular" as CFString, 12, nil)
        return (CTFontCopyFamilyName(f) as String) == "Literata"
    }
}
