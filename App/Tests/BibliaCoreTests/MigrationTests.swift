import Testing
import Foundation
import GRDB
@testable import BibliaCore

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

@Suite struct DateTextTests {
    private var cal: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }
    // 2026-10-29 07:53:00 UTC
    private let t = 1_793_260_380.0

    @Test func datesAreSpanishRegardlessOfSystemLocale() {
        let d = DateText.date(t, calendar: cal)
        #expect(d.contains("oct"), "esperado mes en español, fue \(d)")
        #expect(d.contains("2026") && d.contains("29"))
        #expect(!d.contains("年"))
    }
    @Test func dateTimeAndTime() {
        #expect(DateText.dateTime(t, calendar: cal).contains("7:53") || DateText.dateTime(t, calendar: cal).contains("07:53"))
        #expect(DateText.time(t, calendar: cal).contains(":53"))
    }
}

@Suite struct V10ToV11MigrationTests {
    /// Una base como la de la v1.0 (solo `history` y `search_history`, migración «v1») se abre con la v1.1 sin perder nada.
    @Test func v10DatabaseKeepsHistoryAndGainsAnnotationTables() throws {
        let path = NSTemporaryDirectory() + "v10-\(UUID()).sqlite"
        defer { try? FileManager.default.removeItem(atPath: path) }
        do {
            var m = DatabaseMigrator()
            m.registerMigration("v1") { db in
                try db.execute(sql: """
                    CREATE TABLE history(id INTEGER PRIMARY KEY AUTOINCREMENT, translation_id TEXT NOT NULL,
                      book INTEGER NOT NULL, chapter INTEGER NOT NULL, verse INTEGER,
                      kind TEXT NOT NULL CHECK (kind IN ('page','jump')), at REAL NOT NULL);
                    CREATE INDEX history_at ON history(at DESC);
                    CREATE TABLE search_history(query TEXT PRIMARY KEY, at REAL NOT NULL);
                    INSERT INTO history(translation_id,book,chapter,verse,kind,at) VALUES ('KJV',43,3,16,'jump',1000),('CUV',1,1,NULL,'page',2000);
                    INSERT INTO search_history VALUES ('amor', 5);
                    """)
            }
            let q = try DatabaseQueue(path: path); try m.migrate(q)
        }
        let store = try UserStore(path: path)
        #expect(try store.recentHistory().count == 2)
        #expect(try store.recentSearches() == ["amor"])
        let tables = try store.queue.read { try String.fetchAll($0, sql: "SELECT name FROM sqlite_master WHERE type='table'") }
        #expect(tables.contains("highlights") && tables.contains("notes") && tables.contains("bookmarks"))
        let ann = AnnotationStore(user: store, defaults: UserDefaults(suiteName: "t.\(UUID())")!)
        _ = try ann.addNote(book: 43, chapter: 3, verseStart: 16, body: "hola")
        #expect(try store.recentHistory().count == 2)
        let again = try UserStore(path: path) // reabrir no repite migraciones
        #expect(try again.recentHistory().count == 2)
    }
}
