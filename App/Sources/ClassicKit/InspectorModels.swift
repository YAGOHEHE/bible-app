import AppKit
import BibliaCore

// MARK: - enlaces internos del inspector

/// Enlaces `biblia://go?...` de las filas del inspector (aparición Strong / referencia cruzada) y `biblia://more`.
public enum InspectorLink {
    public static func url(_ ref: BibleRef, translation: String?) -> URL? {
        var s = "biblia://go?b=\(ref.book)&c=\(ref.chapter)"
        if let v = ref.verseFrom { s += "&vf=\(v)&vt=\(ref.verseTo ?? v)" }
        if let t = translation { s += "&t=\(t)" }
        return URL(string: s)
    }

    public static func parse(_ link: Any) -> (ref: BibleRef, translation: String?)? {
        let url: URL?
        if let u = link as? URL { url = u } else if let s = link as? String { url = URL(string: s) } else { url = nil }
        guard let u = url, u.scheme == "biblia", u.host == "go",
              let c = URLComponents(url: u, resolvingAgainstBaseURL: false) else { return nil }
        var q: [String: String] = [:]
        for i in c.queryItems ?? [] { if let v = i.value { q[i.name] = v } }
        guard let b = q["b"].flatMap(Int.init), let ch = q["c"].flatMap(Int.init) else { return nil }
        let vf = q["vf"].flatMap(Int.init)
        return (BibleRef(book: b, chapter: ch, verseFrom: vf, verseTo: q["vt"].flatMap(Int.init) ?? vf), q["t"])
    }

    public static let more = URL(string: "biblia://more")!
    public static func isMore(_ link: Any) -> Bool { "\(link)" == "biblia://more" }
}

// MARK: - Strong

/// Frase del versículo con la palabra pulsada (para mostrarla en negrita).
public struct StrongContext: Equatable {
    public var before: String
    public var word: String
    public var after: String

    public static func make(text: String, start: Int, length: Int, radius: Int = 42) -> StrongContext? {
        let chars = Array(text)
        guard start >= 0, length > 0, start + length <= chars.count else { return nil }
        let lo = max(0, start - radius), hi = min(chars.count, start + length + radius)
        var before = String(chars[lo..<start]), after = String(chars[(start + length)..<hi])
        if lo > 0 {   // no cortar una palabra por la mitad
            if let sp = before.firstIndex(of: " ") { before = String(before[before.index(after: sp)...]) }
            before = "…" + before
        }
        if hi < chars.count {
            if let sp = after.lastIndex(of: " ") { after = String(after[..<sp]) }
            after += "…"
        }
        return StrongContext(before: before, word: String(chars[start..<(start + length)]), after: after)
    }
}

public struct StrongContent: Equatable {
    public var selection: StrongSelection
    public var word: String
    public var context: StrongContext?
    public var contextLabel: String
    public var entry: LexiconEntry?
    public var total: Int
    public var occurrences: [StrongOccurrence]
    public var translationId: String
    public var isHebrew: Bool { selection.strong.uppercased().hasPrefix("H") }
}

public final class StrongInspectorModel {
    public static let occurrenceLimit = 200
    private let lexicon: LexiconRepository
    public init(lexicon: LexiconRepository) { self.lexicon = lexicon }

    public func load(_ sel: StrongSelection, word: String, verseText: String?, length: Int, translationId: String,
                     contextLabel: String) throws -> StrongContent {
        let entry = try lexicon.entry(sel.strong)
        let occ = try lexicon.occurrences(strong: sel.strong, translationId: translationId, limit: Self.occurrenceLimit)
        return StrongContent(selection: sel, word: word,
                             context: verseText.flatMap { StrongContext.make(text: $0, start: sel.start, length: length) },
                             contextLabel: contextLabel, entry: entry, total: occ.total, occurrences: occ.items,
                             translationId: translationId)
    }
}

public enum InspectorFonts {
    static func first(_ names: [String], size: CGFloat) -> NSFont {
        for n in names { if let f = NSFont(name: n, size: size) { return f } }
        return NSFont.systemFont(ofSize: size)
    }
    /// Griego politónico: fuentes de macOS con glifos griegos (el serif de lectura puede no tenerlos en 10.13).
    public static func greek(size: CGFloat) -> NSFont { first(["Palatino", "Times New Roman", "Helvetica Neue"], size: size) }
    public static func hebrew(size: CGFloat) -> NSFont { first(["Times New Roman", "Arial Hebrew", "Lucida Grande"], size: size) }
}

public enum StrongTextBuilder {
    static func label(_ s: String, _ pal: ReaderPalette) -> NSAttributedString {
        let ps = NSMutableParagraphStyle(); ps.paragraphSpacingBefore = 14; ps.paragraphSpacing = 3
        return NSAttributedString(string: s.uppercased() + "\n", attributes: [
            .font: NSFont.systemFont(ofSize: 10.5, weight: .semibold), .foregroundColor: pal.textMuted, .kern: 0.6, .paragraphStyle: ps])
    }

    public static func build(_ c: StrongContent, palette pal: ReaderPalette, bookName: (Int) -> String) -> NSAttributedString {
        let out = NSMutableAttributedString()
        func para(before: CGFloat = 0, after: CGFloat = 0, rtl: Bool = false) -> NSMutableParagraphStyle {
            let p = NSMutableParagraphStyle(); p.paragraphSpacingBefore = before; p.paragraphSpacing = after
            if rtl { p.baseWritingDirection = .rightToLeft; p.alignment = .left }
            return p
        }
        // pastilla + palabra pulsada
        out.append(NSAttributedString(string: "\u{00A0}\(c.selection.strong)\u{00A0}", attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .bold), .foregroundColor: pal.pillText,
            .backgroundColor: pal.pillBackground, .paragraphStyle: para(after: 8)]))
        out.append(NSAttributedString(string: "   «\(c.word)»\n", attributes: [
            .font: NSFontManager.shared.convert(NSFont.systemFont(ofSize: 13), toHaveTrait: .italicFontMask),
            .foregroundColor: pal.textSecondary, .paragraphStyle: para(after: 8)]))
        guard let e = c.entry else {
            out.append(NSAttributedString(string: "Sin entrada en el léxico para \(c.selection.strong).\n", attributes: [
                .font: NSFont.systemFont(ofSize: 13), .foregroundColor: pal.textMuted]))
            appendOccurrences(out, c, pal, bookName)
            return out
        }
        if let l = e.lemma, !l.isEmpty {
            out.append(NSAttributedString(string: l + "\n", attributes: [
                .font: c.isHebrew ? InspectorFonts.hebrew(size: 30) : InspectorFonts.greek(size: 30),
                .foregroundColor: pal.textPrimary, .paragraphStyle: para(after: 4, rtl: c.isHebrew)]))
        }
        if let t = e.translit, !t.isEmpty {
            out.append(NSAttributedString(string: t + "\n", attributes: [
                .font: NSFontManager.shared.convert(NSFont.systemFont(ofSize: 13, weight: .semibold), toHaveTrait: .italicFontMask),
                .foregroundColor: pal.textPrimary]))
        }
        if let p = e.pronunciation, !p.isEmpty {
            out.append(NSAttributedString(string: p + "\n", attributes: [
                .font: NSFont.systemFont(ofSize: 12), .foregroundColor: pal.textSecondary]))
        }
        func body(_ t: String) -> NSAttributedString {
            NSAttributedString(string: t + "\n", attributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: pal.textPrimary,
                                                              .paragraphStyle: para(after: 2)])
        }
        if let d = e.definition, !d.isEmpty { out.append(label("Definición", pal)); out.append(body(d)) }
        if let u = e.kjvUsage, !u.isEmpty { out.append(label("Uso en KJV", pal)); out.append(body(u)) }
        if let ctx = c.context {
            out.append(label("En contexto", pal))
            let f = NSFont.systemFont(ofSize: 13)
            out.append(NSAttributedString(string: c.contextLabel + "  ", attributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: pal.accent]))
            out.append(NSAttributedString(string: ctx.before, attributes: [.font: f, .foregroundColor: pal.textSecondary]))
            out.append(NSAttributedString(string: ctx.word, attributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: .bold), .foregroundColor: pal.textPrimary]))
            out.append(NSAttributedString(string: ctx.after + "\n", attributes: [.font: f, .foregroundColor: pal.textSecondary]))
        }
        appendOccurrences(out, c, pal, bookName)
        return out
    }

    static func appendOccurrences(_ out: NSMutableAttributedString, _ c: StrongContent, _ pal: ReaderPalette,
                                  _ bookName: (Int) -> String) {
        out.append(label("Otras apariciones · \(c.translationId)", pal))
        var count = "\(c.total) \(c.total == 1 ? "versículo" : "versículos")"
        if c.total > c.occurrences.count { count += " · se muestran los primeros \(c.occurrences.count)" }
        out.append(NSAttributedString(string: count + "\n", attributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: pal.textPrimary]))
        for o in c.occurrences {
            let url = InspectorLink.url(o.ref, translation: c.translationId)
            let ps = NSMutableParagraphStyle(); ps.paragraphSpacingBefore = 9
            out.append(NSAttributedString(string: RefLabel.text(bookName: bookName(o.ref.book), ref: o.ref) + "\n", attributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: pal.accent,
                .link: url as Any, .paragraphStyle: ps]))
            let sp = NSMutableParagraphStyle(); sp.paragraphSpacing = 0
            out.append(NSAttributedString(string: o.text.trimmingCharacters(in: .whitespacesAndNewlines) + "\n", attributes: [
                .font: NSFont.systemFont(ofSize: 12), .foregroundColor: pal.textSecondary, .paragraphStyle: sp,
                .link: url as Any]))
        }
    }
}

// MARK: - Referencias cruzadas

public struct RefsContent: Equatable {
    public var header: String
    public var total: Int
    public var rows: [CrossRefRow]
    public var hasMore: Bool { rows.count < total }
}

public final class RefsInspectorModel {
    private let repo: CrossRefRepository
    public init(repo: CrossRefRepository) { self.repo = repo }

    /// Referencias de uno o varios versículos del mismo capítulo (unidas, sin duplicados, por votos).
    /// `text` devuelve el texto de un destino en la versión actual (nil = no existe: se muestra «—»).
    public func load(book: Int, chapter: Int, verses: [Int], bookName: (Int) -> String, text: (BibleRef) -> String?,
                     limit: Int = CrossRefList.pageSize) throws -> RefsContent {
        let vs = Array(Set(verses)).sorted()
        guard let a = vs.first, let b = vs.last else { return RefsContent(header: "", total: 0, rows: []) }
        let merged = CrossRefList.merge(try vs.map { try repo.refs(book: book, chapter: chapter, verse: $0) })
        let rows = merged.prefix(limit).map { CrossRefList.row($0, bookName: bookName, text: text) }
        return RefsContent(header: RefLabel.text(bookName: bookName(book), chapter: chapter, from: a, to: b),
                           total: merged.count, rows: Array(rows))
    }
}

public enum RefsTextBuilder {
    public static func build(_ c: RefsContent, translationId: String, palette pal: ReaderPalette, empty: String? = nil) -> NSAttributedString {
        let out = NSMutableAttributedString()
        let hp = NSMutableParagraphStyle(); hp.paragraphSpacing = 2
        out.append(NSAttributedString(string: c.header + "\n", attributes: [
            .font: NSFont.systemFont(ofSize: 14, weight: .bold), .foregroundColor: pal.heading, .paragraphStyle: hp]))
        let sub = c.total == 0 ? "Sin referencias cruzadas" :
            "\(c.total) \(c.total == 1 ? "referencia" : "referencias") · de más a menos votadas"
        out.append(NSAttributedString(string: sub + "\n", attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: pal.textMuted]))
        for r in c.rows {
            let url = InspectorLink.url(r.target, translation: nil)
            let lp = NSMutableParagraphStyle(); lp.paragraphSpacingBefore = 10
            lp.tabStops = [NSTextTab(textAlignment: .right, location: 250, options: [:])]
            out.append(NSAttributedString(string: r.label, attributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: pal.accent, .link: url as Any, .paragraphStyle: lp]))
            out.append(NSAttributedString(string: "  \(r.votes)\n", attributes: [
                .font: NSFont.systemFont(ofSize: 10.5), .foregroundColor: pal.textMuted, .paragraphStyle: lp]))
            out.append(NSAttributedString(string: (r.snippet ?? "—") + "\n", attributes: [
                .font: NSFont.systemFont(ofSize: 12), .foregroundColor: r.snippet == nil ? pal.textMuted : pal.textSecondary,
                .link: url as Any]))
        }
        if c.hasMore {
            let mp = NSMutableParagraphStyle(); mp.paragraphSpacingBefore = 14; mp.alignment = .center
            out.append(NSAttributedString(string: "Mostrar más (\(c.total - c.rows.count))\n", attributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: pal.accent,
                .link: InspectorLink.more, .paragraphStyle: mp]))
        }
        return out
    }
}

// MARK: - Historial (S07)

public struct HistoryRow: Equatable, Identifiable {
    public var entry: HistoryEntry
    public var label: String
    public var translationId: String
    public var kind: String
    public var time: String
    public var id: Int64 { entry.id }
    public var ref: BibleRef { BibleRef(book: entry.book, chapter: entry.chapter, verseFrom: entry.verse, verseTo: entry.verse) }
}

public struct HistorySection: Equatable {
    public var title: String
    public var rows: [HistoryRow]
}

public enum HistoryModel {
    public static func kindLabel(_ k: String) -> String { k == "page" ? "Pasar página" : "Salto" }

    /// Entradas (más reciente primero) -> secciones Hoy / Ayer / fecha; la referencia usa el idioma de la versión.
    public static func sections(_ entries: [HistoryEntry], bookName: (String, Int) -> String,
                                now: Date = Date(), calendar: Calendar = .current) -> [HistorySection] {
        HistoryGrouping.group(entries, now: now, calendar: calendar).map { day in
            HistorySection(title: day.title, rows: day.entries.map { e in
                HistoryRow(entry: e,
                           label: RefLabel.text(bookName: bookName(e.translationId, e.book), chapter: e.chapter, from: e.verse, to: e.verse),
                           translationId: e.translationId, kind: kindLabel(e.kind),
                           time: DateText.time(e.at, calendar: calendar))
            })
        }
    }
}
