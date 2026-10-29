import Foundation
import GRDB

public enum BibleDatabaseError: Error { case notFound }

/// Abre bible.sqlite en solo lectura. Un DatabaseQueue de solo lectura basta (consultas de
/// milisegundos) y evita que GRDB intente activar WAL sobre un fichero firmado/solo lectura.
public final class BibleDatabase {
    public let reader: DatabaseQueue

    public init(path: String) throws {
        var config = Configuration()
        config.readonly = true
        reader = try DatabaseQueue(path: path, configuration: config)
    }

    /// Busca el paquete de recursos de SwiftPM sin usar `Bundle.module` (que hace fatalError si
    /// no lo encuentra: dentro del .app el bundle está en Contents/Resources, no en la raíz).
    public static func resourceBundleURL() -> URL? {
        let fm = FileManager.default
        // The resources now belong to the BibliaCore target (shared by the SwiftUI and AppKit apps).
        for name in ["BibliaApp_BibliaCore.bundle", "BibliaApp_BibliaApp.bundle"] {
            if let u = bundleCandidates().map({ $0.appendingPathComponent(name) }).first(where: { fm.fileExists(atPath: $0.path) }) { return u }
        }
        return nil
    }

    private static func bundleCandidates() -> [URL] {
        return [
            Bundle.main.resourceURL,                       // .app: Contents/Resources
            Bundle.main.bundleURL,                         // swift run: junto al ejecutable
            Bundle.main.executableURL?.deletingLastPathComponent(),
        ].compactMap { $0 }
    }

    public static func bundledPath() -> String? {
        let fm = FileManager.default
        if let b = resourceBundleURL() {
            for rel in ["Resources/bible.sqlite", "bible.sqlite"] {
                let p = b.appendingPathComponent(rel).path
                if fm.fileExists(atPath: p) { return p }
            }
        }
        if let env = ProcessInfo.processInfo.environment["BIBLIA_DB"], fm.fileExists(atPath: env) { return env }
        // Desarrollo: App/Resources/bible.sqlite relativo a este fichero fuente.
        let dev = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/bible.sqlite").path
        return fm.fileExists(atPath: dev) ? dev : nil
    }

    public static func openBundled() throws -> BibleDatabase {
        guard let p = bundledPath() else { throw BibleDatabaseError.notFound }
        return try BibleDatabase(path: p)
    }
}
