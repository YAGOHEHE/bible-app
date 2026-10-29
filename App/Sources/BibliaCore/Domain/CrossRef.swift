import Foundation
import GRDB

/// Referencia cruzada desde un versículo a otro (o a un rango de versículos del mismo capítulo).
/// Fuente: OpenBible.info (CC BY); `votes` es la relevancia según los usuarios.
public struct CrossRef: Equatable, Hashable, FetchableRecord {
    public var book: Int
    public var chapter: Int
    public var verse: Int
    public var toBook: Int
    public var toChapter: Int
    public var toVerseStart: Int
    public var toVerseEnd: Int
    public var votes: Int

    public init(book: Int, chapter: Int, verse: Int, toBook: Int, toChapter: Int,
         toVerseStart: Int, toVerseEnd: Int, votes: Int) {
        self.book = book; self.chapter = chapter; self.verse = verse
        self.toBook = toBook; self.toChapter = toChapter
        self.toVerseStart = toVerseStart; self.toVerseEnd = toVerseEnd; self.votes = votes
    }

    public init(row: Row) {
        book = row["book"]; chapter = row["chapter"]; verse = row["verse"]
        toBook = row["to_book"]; toChapter = row["to_chapter"]
        toVerseStart = row["to_verse_start"]; toVerseEnd = row["to_verse_end"]
        votes = row["votes"]
    }

    /// Destino como `BibleRef` (rango de versículos si `toVerseEnd > toVerseStart`).
    public var target: BibleRef {
        BibleRef(book: toBook, chapter: toChapter, verseFrom: toVerseStart, verseTo: toVerseEnd)
    }
}
