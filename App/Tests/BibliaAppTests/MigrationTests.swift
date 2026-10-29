import Testing
import Foundation
@testable import BibliaApp

@Suite struct MigrationTests {
    private func suite(_ n: String) -> UserDefaults {
        let d = UserDefaults(suiteName: n)!; d.removePersistentDomain(forName: n); return d
    }

    @Test func defaultsCopiedWhenNewIsEmpty() {
        let oldN = "test.old.\(UUID())", newN = "test.new.\(UUID())"
        let old = suite(oldN); old.set(1.4, forKey: "set.fontScale"); old.set("KJV", forKey: "set.defaultTranslation")
        let new = suite(newN)
        let did = LegacyMigration.migrateDefaults(into: new, newDomain: newN, legacyDomain: oldN,
                                                  legacySource: { UserDefaults.standard.persistentDomain(forName: $0) })
        #expect(did)
        #expect(new.double(forKey: "set.fontScale") == 1.4)
        #expect(new.string(forKey: "set.defaultTranslation") == "KJV")
        #expect(old.double(forKey: "set.fontScale") == 1.4) // el antiguo se conserva
        // Segunda ejecución: no hace nada
        old.set(2.0, forKey: "set.fontScale")
        #expect(!LegacyMigration.migrateDefaults(into: new, newDomain: newN, legacyDomain: oldN))
        #expect(new.double(forKey: "set.fontScale") == 1.4)
        old.removePersistentDomain(forName: oldN); new.removePersistentDomain(forName: newN)
    }

    @Test func defaultsNotOverwrittenWhenNewHasData() {
        let oldN = "test.old.\(UUID())", newN = "test.new.\(UUID())"
        let old = suite(oldN); old.set("KJV", forKey: "set.defaultTranslation")
        let new = suite(newN); new.set("ASV", forKey: "set.defaultTranslation")
        #expect(!LegacyMigration.migrateDefaults(into: new, newDomain: newN, legacyDomain: oldN))
        #expect(new.string(forKey: "set.defaultTranslation") == "ASV")
        old.removePersistentDomain(forName: oldN); new.removePersistentDomain(forName: newN)
    }

    @Test func userDataCopiedNotMovedNotOverwritten() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("mig-\(UUID())")
        let oldDir = root.appendingPathComponent("BibliaApp"), newDir = root.appendingPathComponent("Biblia")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: oldDir, withIntermediateDirectories: true)
        let u = try UserStore(path: oldDir.appendingPathComponent("user.sqlite").path)
        try u.addSearch("amor")
        #expect(LegacyMigration.migrateUserData(legacyDir: oldDir, newDir: newDir))
        #expect(FileManager.default.fileExists(atPath: oldDir.appendingPathComponent("user.sqlite").path))
        let n = try UserStore(path: newDir.appendingPathComponent("user.sqlite").path)
        #expect(try n.recentSearches() == ["amor"])
        try n.addSearch("paz")
        #expect(!LegacyMigration.migrateUserData(legacyDir: oldDir, newDir: newDir)) // destino existe
        #expect(try n.recentSearches().contains("paz"))
    }

    @Test func noLegacyNoop() {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("mig-\(UUID())")
        #expect(!LegacyMigration.migrateUserData(legacyDir: root.appendingPathComponent("x"), newDir: root.appendingPathComponent("y")))
    }
}
