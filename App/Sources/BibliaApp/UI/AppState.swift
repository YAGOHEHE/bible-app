import Foundation
import Observation

/// Estado único de la app (@Observable, macOS 14).
@Observable
@MainActor
final class AppState {
    enum Load { case loading, missingData, failed(String), ready }

    var load: Load = .loading
    var translations: [Translation] = []
    var currentTranslation = "CUV"
    var bookNames: [BookName] = []
    var selectedBook: Int? = 1
    var chapter = 1
    var verses: [Verse] = []
    var headings: [Heading] = []
    var highlightedVerse: Int?

    var bible: BibleDatabase?
    var user: UserStore?
    private var verseRepo: VerseRepository?

    func bootstrap() {
        user = try? UserStore.defaultURL().path.pipe { try UserStore(path: $0) }
        do {
            let db = try BibleDatabase.openBundled()
            bible = db
            verseRepo = VerseRepository(db: db)
            translations = try TranslationRepository(db: db).all()
            if !translations.contains(where: { $0.id == currentTranslation }), let f = translations.first {
                currentTranslation = f.id
            }
            let lang = translations.first { $0.id == currentTranslation }?.language ?? "es"
            bookNames = try TranslationRepository(db: db).bookNames(language: lang)
            load = .ready
            reloadChapter()
        } catch BibleDatabaseError.notFound {
            load = .missingData
        } catch {
            load = .failed("\(error)")
        }
    }

    func reloadChapter() {
        guard let repo = verseRepo, let book = selectedBook else { return }
        do {
            verses = try repo.chapter(translationId: currentTranslation, book: book, chapter: chapter)
            headings = try repo.headings(translationId: currentTranslation, book: book, chapter: chapter)
        } catch {
            load = .failed("\(error)")
        }
    }

    func select(book: Int) { selectedBook = book; chapter = 1; reloadChapter() }

    func bookName(_ n: Int) -> String {
        bookNames.first { $0.book == n }?.name ?? ReferenceParser.books[n - 1].2
    }
}

private extension String {
    func pipe<T>(_ f: (String) throws -> T) rethrows -> T { try f(self) }
}
