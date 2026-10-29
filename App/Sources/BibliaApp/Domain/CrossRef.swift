import Foundation
import GRDB

/// Referencia cruzada desde un versículo a otro (o a un rango de versículos del mismo capítulo).
/// Fuente: OpenBible.info (CC BY); `votes` es la relevancia según los usuarios.
struct CrossRef: Equatable, Hashable, FetchableRecord {
    var book: Int
    var chapter: Int
    var verse: Int
    var toBook: Int
    var toChapter: Int
    var toVerseStart: Int
    var toVerseEnd: Int
    var votes: Int

    init(book: Int, chapter: Int, verse: Int, toBook: Int, toChapter: Int,
         toVerseStart: Int, toVerseEnd: Int, votes: Int) {
        self.book = book; self.chapter = chapter; self.verse = verse
        self.toBook = toBook; self.toChapter = toChapter
        self.toVerseStart = toVerseStart; self.toVerseEnd = toVerseEnd; self.votes = votes
    }

    init(row: Row) {
        book = row["book"]; chapter = row["chapter"]; verse = row["verse"]
        toBook = row["to_book"]; toChapter = row["to_chapter"]
        toVerseStart = row["to_verse_start"]; toVerseEnd = row["to_verse_end"]
        votes = row["votes"]
    }

    /// Destino como `BibleRef` (rango de versículos si `toVerseEnd > toVerseStart`).
    var target: BibleRef {
        BibleRef(book: toBook, chapter: toChapter, verseFrom: toVerseStart, verseTo: toVerseEnd)
    }
}
