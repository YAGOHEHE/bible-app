import AppKit

/// Markdown → NSAttributedString compatible con macOS 10.13 (`AttributedString(markdown:)` es de macOS 12).
/// Soporta: **negrita**, *cursiva* / _cursiva_, `código`, títulos # y ##(#), listas con viñetas (-, *, +) y numeradas,
/// citas (>) y enlaces [texto](url). Nunca falla: lo que no reconoce queda como texto.
public enum MarkdownRenderer {
    public struct Style {
        public var fontSize: CGFloat
        public var text: NSColor
        public var muted: NSColor
        public var link: NSColor
        public var codeBackground: NSColor
        public init(fontSize: CGFloat = 13, text: NSColor = .labelColor, muted: NSColor = .secondaryLabelColor,
                    link: NSColor = .blue, codeBackground: NSColor = NSColor(white: 0.5, alpha: 0.18)) {
            self.fontSize = fontSize; self.text = text; self.muted = muted; self.link = link; self.codeBackground = codeBackground
        }
    }

    private struct Traits { var bold = false, italic = false }

    public static func render(_ source: String, style: Style = Style()) -> NSAttributedString {
        let out = NSMutableAttributedString()
        let lines = source.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        for (i, raw) in lines.enumerated() {
            out.append(block(raw, style))
            if i < lines.count - 1 { out.append(NSAttributedString(string: "\n", attributes: [.font: NSFont.systemFont(ofSize: style.fontSize)])) }
        }
        return out
    }

    // MARK: bloques

    private static func para(indent: CGFloat = 0, hang: CGFloat = 0, before: CGFloat = 0, after: CGFloat = 2) -> NSParagraphStyle {
        let p = NSMutableParagraphStyle()
        p.firstLineHeadIndent = indent
        p.headIndent = indent + hang
        p.paragraphSpacingBefore = before
        p.paragraphSpacing = after
        p.lineBreakMode = .byWordWrapping
        return p
    }

    private static func block(_ raw: String, _ st: Style) -> NSAttributedString {
        let line = raw
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let leading = CGFloat(line.prefix { $0 == " " || $0 == "\t" }.count)

        // títulos: # .. ######
        if trimmed.hasPrefix("#") {
            let hashes = trimmed.prefix { $0 == "#" }
            let rest = trimmed.dropFirst(hashes.count)
            if (1...6).contains(hashes.count), rest.first == " " || rest.isEmpty {
                let size: CGFloat = hashes.count == 1 ? st.fontSize * 1.5 : (hashes.count == 2 ? st.fontSize * 1.25 : st.fontSize * 1.1)
                let body = inline(String(rest).trimmingCharacters(in: .whitespaces), st, Traits(bold: true), size: size, color: st.text)
                body.addAttribute(.paragraphStyle, value: para(before: 4, after: 3), range: NSRange(location: 0, length: body.length))
                return body
            }
        }
        // cita
        if trimmed.hasPrefix(">") {
            var rest = trimmed.dropFirst()
            if rest.first == " " { rest = rest.dropFirst() }
            let body = NSMutableAttributedString(string: "\u{258F} ", attributes: [
                .font: NSFont.systemFont(ofSize: st.fontSize), .foregroundColor: st.muted])
            body.append(inline(String(rest), st, Traits(italic: true), size: st.fontSize, color: st.muted))
            body.addAttribute(.paragraphStyle, value: para(indent: 6, hang: 12), range: NSRange(location: 0, length: body.length))
            return body
        }
        // lista con viñetas
        if let m = trimmed.first, "-*+".contains(m), trimmed.dropFirst().first == " " {
            let body = NSMutableAttributedString(string: "\u{2022}\t", attributes: [
                .font: NSFont.systemFont(ofSize: st.fontSize), .foregroundColor: st.text])
            body.append(inline(String(trimmed.dropFirst(2)), st, Traits(), size: st.fontSize, color: st.text))
            body.addAttribute(.paragraphStyle, value: listPara(level: leading), range: NSRange(location: 0, length: body.length))
            return body
        }
        // lista numerada: «1. »
        let digits = trimmed.prefix { $0.isASCII && $0.isNumber }
        if !digits.isEmpty, digits.count <= 3, trimmed.dropFirst(digits.count).hasPrefix(". ") {
            let body = NSMutableAttributedString(string: "\(digits).\t", attributes: [
                .font: NSFont.systemFont(ofSize: st.fontSize), .foregroundColor: st.text])
            body.append(inline(String(trimmed.dropFirst(digits.count + 2)), st, Traits(), size: st.fontSize, color: st.text))
            body.addAttribute(.paragraphStyle, value: listPara(level: leading), range: NSRange(location: 0, length: body.length))
            return body
        }
        let body = inline(line, st, Traits(), size: st.fontSize, color: st.text)
        body.addAttribute(.paragraphStyle, value: para(), range: NSRange(location: 0, length: body.length))
        return body
    }

    private static func listPara(level: CGFloat) -> NSParagraphStyle {
        let p = NSMutableParagraphStyle()
        let base = 6 + min(level, 8) * 4
        p.firstLineHeadIndent = base
        p.headIndent = base + 14
        p.tabStops = [NSTextTab(textAlignment: .left, location: base + 14, options: [:])]
        p.paragraphSpacing = 2
        return p
    }

    // MARK: en línea

    private static func font(_ st: Style, size: CGFloat, _ t: Traits) -> NSFont {
        var f = NSFont.systemFont(ofSize: size)
        let fm = NSFontManager.shared
        if t.bold { f = fm.convert(f, toHaveTrait: .boldFontMask) }
        if t.italic { f = fm.convert(f, toHaveTrait: .italicFontMask) }
        return f
    }

    static func codeFont(size: CGFloat) -> NSFont {
        NSFont(name: "Menlo", size: size * 0.92) ?? NSFont.userFixedPitchFont(ofSize: size * 0.92) ?? NSFont.systemFont(ofSize: size)
    }

    private static func inline(_ s: String, _ st: Style, _ t: Traits, size: CGFloat, color: NSColor) -> NSMutableAttributedString {
        let out = NSMutableAttributedString()
        let chars = Array(s)
        var buf = ""
        func flush() {
            guard !buf.isEmpty else { return }
            out.append(NSAttributedString(string: buf, attributes: [.font: font(st, size: size, t), .foregroundColor: color]))
            buf = ""
        }
        func find(_ delim: [Character], from: Int) -> Int? {
            var j = from
            while j + delim.count <= chars.count {
                if chars[j] == "\\" { j += 2; continue }
                if Array(chars[j..<(j + delim.count)]) == delim { return j }
                j += 1
            }
            return nil
        }
        func isAlnum(_ i: Int) -> Bool { i >= 0 && i < chars.count && (chars[i].isLetter || chars[i].isNumber) }
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == "\\", i + 1 < chars.count, "\\`*_[]()#>-+.!".contains(chars[i + 1]) {
                buf.append(chars[i + 1]); i += 2; continue
            }
            if c == "`", let end = chars[(i + 1)...].firstIndex(of: "`"), end > i + 1 {
                flush()
                out.append(NSAttributedString(string: String(chars[(i + 1)..<end]), attributes: [
                    .font: codeFont(size: size), .foregroundColor: color, .backgroundColor: st.codeBackground]))
                i = end + 1; continue
            }
            if c == "[", let close = find(["]", "("], from: i + 1), let paren = find([")"], from: close + 2) {
                let label = String(chars[(i + 1)..<close]), target = String(chars[(close + 2)..<paren]).trimmingCharacters(in: .whitespaces)
                if !label.isEmpty, let url = URL(string: target), url.scheme != nil {
                    flush()
                    let inner = inline(label, st, t, size: size, color: st.link)
                    inner.addAttributes([.link: url, .underlineStyle: NSUnderlineStyle.single.rawValue, .foregroundColor: st.link],
                                        range: NSRange(location: 0, length: inner.length))
                    out.append(inner)
                    i = paren + 1; continue
                }
            }
            if c == "*" || c == "_" {
                let triple = i + 2 < chars.count && chars[i + 1] == c && chars[i + 2] == c
                let double = i + 1 < chars.count && chars[i + 1] == c
                let opens = c == "*" || !isAlnum(i - 1)
                if opens, triple, let end = find([c, c, c], from: i + 3), end > i + 3 {
                    flush()
                    out.append(inline(String(chars[(i + 3)..<end]), st, Traits(bold: true, italic: true), size: size, color: color))
                    i = end + 3; continue
                }
                if opens, double, let end = find([c, c], from: i + 2), end > i + 2, !chars[i + 2].isWhitespace {
                    flush()
                    out.append(inline(String(chars[(i + 2)..<end]), st, Traits(bold: true, italic: t.italic), size: size, color: color))
                    i = end + 2; continue
                }
                if opens, !double, i + 1 < chars.count, !chars[i + 1].isWhitespace, let end = find([c], from: i + 1), end > i + 1,
                   !chars[end - 1].isWhitespace, c == "*" || !isAlnum(end + 1) {
                    flush()
                    out.append(inline(String(chars[(i + 1)..<end]), st, Traits(bold: t.bold, italic: true), size: size, color: color))
                    i = end + 1; continue
                }
            }
            buf.append(c); i += 1
        }
        flush()
        return out
    }
}
