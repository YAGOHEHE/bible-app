import BibliaCore
import Foundation

// Moved out of BibliaCore: AttributedString(markdown:) needs macOS 12. The classic app renders Markdown itself (L4).
/// Vista previa de Markdown: nunca lanza; si el análisis falla, texto plano.
@available(macOS 14, *)
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

