import Foundation

/// Vista previa de Markdown: nunca lanza; si el análisis falla, texto plano.
enum MarkdownPreview {
    static func render(_ source: String) -> AttributedString {
        let opts = AttributedString.MarkdownParsingOptions(
            allowsExtendedAttributes: false,
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible)
        if let a = try? AttributedString(markdown: source, options: opts) { return a }
        return AttributedString(source)
    }
}

/// Referencia legible en el idioma de la versión: «1 Juan 4:9–10», «约翰福音 3:16».
enum RefLabel {
    static func text(bookName: String, chapter: Int, from: Int?, to: Int?) -> String {
        guard let a = from else { return "\(bookName) \(chapter)" }
        let b = max(a, to ?? a)
        return "\(bookName) \(chapter):" + (a == b ? "\(a)" : "\(a)–\(b)")
    }

    static func text(bookName: String, ref: BibleRef) -> String {
        text(bookName: bookName, chapter: ref.chapter, from: ref.verseFrom, to: ref.verseTo)
    }
}
