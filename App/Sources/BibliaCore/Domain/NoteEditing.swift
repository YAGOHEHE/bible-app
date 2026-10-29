import Foundation

/// Referencia legible en el idioma de la versión: «1 Juan 4:9–10», «约翰福音 3:16».
public enum RefLabel {
    public static func text(bookName: String, chapter: Int, from: Int?, to: Int?) -> String {
        guard let a = from else { return "\(bookName) \(chapter)" }
        let b = max(a, to ?? a)
        return "\(bookName) \(chapter):" + (a == b ? "\(a)" : "\(a)–\(b)")
    }

    public static func text(bookName: String, ref: BibleRef) -> String {
        text(bookName: bookName, chapter: ref.chapter, from: ref.verseFrom, to: ref.verseTo)
    }
}
