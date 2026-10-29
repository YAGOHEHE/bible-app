import Foundation

/// Migración única desde la marca provisional (`org.bibliaapp.reader`, carpeta "BibliaApp")
/// a la definitiva (`org.biblia.lector`, carpeta "Biblia"). Copia, nunca borra lo antiguo.
enum LegacyMigration {
    static let newBundleID = "org.biblia.lector"
    static let legacyBundleID = "org.bibliaapp.reader"
    static let legacyFolder = "BibliaApp"
    static let newFolder = "Biblia"
    static let markerKey = "migration.fromBibliaApp.done"

    /// Copia las claves de UserDefaults del dominio antiguo si el nuevo no tiene datos propios.
    /// Devuelve true si copió algo.
    @discardableResult
    static func migrateDefaults(into new: UserDefaults, newDomain: String, legacyDomain: String = legacyBundleID,
                                legacySource: (String) -> [String: Any]? = { UserDefaults.standard.persistentDomain(forName: $0) }) -> Bool {
        if new.bool(forKey: markerKey) { return false }
        defer { new.set(true, forKey: markerKey) }
        let existing = new.persistentDomain(forName: newDomain) ?? [:]
        guard existing.isEmpty, let old = legacySource(legacyDomain), !old.isEmpty else { return false }
        for (k, v) in old { new.set(v, forKey: k) }
        return true
    }

    /// Copia `<legacyDir>/user.sqlite` (y -wal/-shm) a `<newDir>/user.sqlite` si el destino no existe.
    @discardableResult
    static func migrateUserData(legacyDir: URL, newDir: URL) -> Bool {
        let fm = FileManager.default
        let src = legacyDir.appendingPathComponent("user.sqlite")
        let dst = newDir.appendingPathComponent("user.sqlite")
        guard fm.fileExists(atPath: src.path), !fm.fileExists(atPath: dst.path) else { return false }
        do {
            try fm.createDirectory(at: newDir, withIntermediateDirectories: true)
            for suffix in ["", "-wal", "-shm"] {
                let s = legacyDir.appendingPathComponent("user.sqlite" + suffix)
                if fm.fileExists(atPath: s.path) { try fm.copyItem(at: s, to: newDir.appendingPathComponent("user.sqlite" + suffix)) }
            }
            return true
        } catch { return false }
    }

    /// Punto de entrada de la app: migra datos de usuario de las rutas reales.
    static func runAtLaunch() {
        guard Bundle.main.bundleIdentifier == newBundleID else { return }
        migrateDefaults(into: .standard, newDomain: newBundleID)
        if let base = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true) {
            migrateUserData(legacyDir: base.appendingPathComponent(legacyFolder, isDirectory: true),
                            newDir: base.appendingPathComponent(newFolder, isDirectory: true))
        }
    }
}
