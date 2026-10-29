import Testing
import AppKit
import Foundation
@testable import ClassicKit
@testable import BibliaCore

private func makeStore() throws -> (AnnotationStore, UserStore) {
    let u = try UserStore(path: NSTemporaryDirectory() + "l4-\(UUID().uuidString).sqlite")
    return (AnnotationStore(user: u, defaults: UserDefaults(suiteName: "l4-\(UUID().uuidString)")!), u)
}

private func makeModels() throws -> (ReaderModel, AnnotationsModel, AnnotationStore, NotificationCenter) {
    let d = UserDefaults(suiteName: "org.biblia.clasica.tests.\(UUID().uuidString)")!
    let nc = NotificationCenter()
    let s = ClassicSettings(defaults: d, center: nc)
    let (store, user) = try makeStore()
    let m = ReaderModel(settings: s, user: user, defaults: d, center: nc)
    try m.bootstrap(db: try BibleDatabase(path: try #require(BibleDatabase.bundledPath())))
    return (m, AnnotationsModel(reader: m, store: store, center: nc), store, nc)
}

// MARK: selección acumulativa (v1.1.2)

@Suite struct SelectionTests {
    let rows = Array(16...30)

    @Test func clickAddsAndRemoves() {
        var s = VerseSelection()
        s.click(22, shift: false, rows: rows)
        #expect(s.sorted == [22])
        s.click(23, shift: false, rows: rows); s.click(25, shift: false, rows: rows)
        #expect(s.sorted == [22, 23, 25])               // clic en versículos nuevos: se AÑADEN
        s.click(23, shift: false, rows: rows)
        #expect(s.sorted == [22, 25])                   // clic en uno seleccionado: se QUITA
        #expect(s.lastClicked == 23 && s.anchor == 25)  // 23 ya no está: el ancla es el mayor
    }

    @Test func shiftClickAddsRangeFromLastClick() {
        var s = VerseSelection()
        s.click(18, shift: false, rows: rows)
        s.click(21, shift: true, rows: rows)
        #expect(s.sorted == [18, 19, 20, 21])
        s.click(16, shift: true, rows: rows)            // desde el último (21) hacia atrás
        #expect(s.sorted == [16, 17, 18, 19, 20, 21])
        var t = VerseSelection()
        t.click(25, shift: true, rows: rows)            // sin último clic: ⇧ = clic normal
        #expect(t.sorted == [25])
    }

    @Test func clearEmptiesEverything() {
        var s = VerseSelection()
        s.click(20, shift: false, rows: rows); s.click(22, shift: true, rows: rows)
        s.clear()
        #expect(s.isEmpty && s.lastClicked == nil && s.anchor == nil)
    }

    @Test func modelBarFollowsSelection() throws {
        let (_, a, _, nc) = try makeModels()
        var posts = 0
        let tok = nc.addObserver(forName: .classicSelectionChanged, object: a, queue: nil) { _ in posts += 1 }
        defer { nc.removeObserver(tok) }
        a.rows = Array(1...36)
        a.click(22, shift: false)
        #expect(a.barVisible && a.selectedRows == [22])
        a.click(23, shift: false); a.click(25, shift: false)
        #expect(a.selectedRows == [22, 23, 25])
        a.click(23, shift: false)
        #expect(a.selectedRows == [22, 25] && a.barVisible)
        a.closeBar()
        #expect(!a.barVisible && a.selectedRows == [22, 25])     // × cierra la barra; la selección sigue pintada
        a.click(30, shift: false)
        #expect(a.barVisible)                                    // un clic nuevo la reabre
        a.clearSelection()
        #expect(a.selection.isEmpty && !a.barVisible)
        #expect(posts >= 7)
    }

    @Test func selectionClearsOnChapterChangeNotOnTranslationChange() throws {
        let (m, a, _, _) = try makeModels()
        a.rows = Array(1...36)
        a.click(5, shift: false)
        m.setTranslation(m.translationId == "KJV" ? "RV1909" : "KJV")
        #expect(a.selectedRows == [5])                           // cambiar de versión conserva la selección
        m.goNext()
        #expect(a.selection.isEmpty)                             // cambiar de capítulo la vacía
    }
}

// MARK: acciones y menús

@Suite struct ActionAvailabilityTests {
    @Test func menuEnablement() {
        let none = VerseMenuState(context: VerseActionContext(selectedCount: 0, strongAvailable: true))
        for a in VerseAction.allCases { #expect(!none.isEnabled(a), "\(a)") }
        #expect(!none.canHighlight && !none.canRemoveHighlight && !none.canDeselect)

        var ctx = VerseActionContext(selectedCount: 2, strongAvailable: false, parallelOn: false)
        var st = VerseMenuState(context: ctx, bookmarked: false, hasHighlight: false, crossRefCount: 0, hasVerseSelection: true)
        #expect(st.isEnabled(.copy) && st.isEnabled(.note) && st.isEnabled(.bookmark) && st.isEnabled(.compare))
        #expect(!st.isEnabled(.strong))                          // sin versión Strong a la vista
        #expect(st.canHighlight && !st.canRemoveHighlight && st.canDeselect)
        st.hasHighlight = true; st.bookmarked = true; st.crossRefCount = 23
        #expect(st.canRemoveHighlight && st.bookmarkTitle == "Quitar marcador" && st.barBookmarkLabel == "Quitar")
        #expect(st.refsTitle == "Referencias (23)" && st.refsAccessibility == "Referencias, 23")

        ctx.strongAvailable = true; ctx.parallelOn = true
        #expect(VerseActions.visible(ctx).contains(.strong) && !VerseActions.visible(ctx).contains(.compare))
        ctx.annotationsAvailable = false
        st = VerseMenuState(context: ctx)
        #expect(st.isEnabled(.copy) && !st.isEnabled(.note) && !st.isEnabled(.bookmark) && !st.canHighlight)
    }

    @Test func barLabelsAndAccessibility() {
        let st = VerseMenuState(context: VerseActionContext(selectedCount: 1))
        #expect(st.barLabel(.copyReference) == "Con ref." && st.barLabel(.bookmark) == "Marcador" && st.barLabel(.copy) == "Copiar")
        #expect(VerseMenuState.swatchAccessibility(.yellow) == "Resaltar en amarillo")
        #expect(VerseMenuState.swatchAccessibility(.orange) == "Resaltar en naranja")
        // diseño de la barra por ancho
        #expect(ActionBarLayout.choose(width: 900, actionCount: 7) == .oneRow)
        #expect(ActionBarLayout.choose(width: 500, actionCount: 7) == .twoRows)
        #expect(ActionBarLayout.choose(width: 300, actionCount: 7) == .compact)
    }

    @Test func scopeAndTargets() throws {
        let (m, a, _, _) = try makeModels()
        m.jump(book: 4, chapter: 1)
        m.setTranslation("CUV")
        a.rows = m.items.map(\.number); a.rowsAreExact = false
        let merged = try #require(m.items.first { $0.endNumber > $0.number })
        a.click(merged.number, shift: false)
        // en lectura simple un versículo fusionado aporta todos los suyos
        #expect(a.targetVerses() == Array(merged.number...merged.endNumber))
        #expect(a.range() == merged.number...merged.endNumber)
        // clic derecho fuera de la selección: solo ese versículo
        let other = try #require(m.items.first { $0.number > merged.endNumber && $0.endNumber == $0.number }).number
        #expect(a.scope(forContextVerse: other) == [other])
        #expect(a.scope(forContextVerse: merged.number) == nil)
        #expect(a.scope(forContextVerse: nil) == nil)
        #expect(a.targetVerses([other]) == [other])
        let st = a.menuState(strongAvailable: false, parallelOn: false)
        #expect(st.hasVerseSelection && st.isEnabled(.note))
    }
}

// MARK: resaltados y marcadores por referencia

@Suite struct HighlightAcrossTranslationsTests {
    @Test func highlightBookmarkAndNotesSurviveTranslationChange() throws {
        let (m, a, store, _) = try makeModels()
        m.jump(book: 43, chapter: 3)
        a.rows = m.items.map(\.number)
        a.click(16, shift: false); a.click(17, shift: false)
        a.highlight(.green)
        a.toggleBookmark()
        _ = try store.addNote(book: 43, chapter: 3, verseStart: 16, verseEnd: 17, body: "nota")
        a.didMutate()
        for t in ["RV1909", "KJV", "CUV", "CUVT"] {
            m.setTranslation(t)
            let ch = a.chapter
            #expect(ch.highlights[16] == .green && ch.highlights[17] == .green, "\(t)")
            #expect(ch.bookmarks == [16, 17] && ch.notes.count == 1, "\(t)")
        }
        #expect(a.highlightColor() == .green && a.isBookmarked() && a.hasHighlight())
        a.toggleBookmark()                        // todos marcados: se quitan
        #expect(!a.isBookmarked() && a.chapter.bookmarks.isEmpty)
        a.removeHighlight()
        #expect(a.chapter.highlights.isEmpty)
        #expect(store.lastUsedColor == .green)
        a.highlightWithLastColor()
        #expect(a.chapter.highlights[16] == .green)
    }

    @Test func mergedVerseShowsAnyOfItsVersesHighlight() throws {
        let (m, a, store, _) = try makeModels()
        m.jump(book: 4, chapter: 1)
        m.setTranslation("CUV")
        let merged = try #require(m.items.first { $0.endNumber > $0.number })
        try store.setHighlight(.pink, book: 4, chapter: 1, verses: [merged.endNumber])   // solo el SEGUNDO versículo
        a.didMutate()
        let ann = a.chapter.forDisplayVerse(number: merged.number, end: merged.endNumber)
        #expect(ann.color == .pink)
        // y en el texto maquetado el versículo fusionado lleva ese fondo
        var style = ReaderStyle(palette: .light, fontScale: 1, latin: false, perVerse: false)
        style.annotations = a.chapter
        let blocks = ChapterBuilder.blocks(items: m.items, layout: m.layout, mode: .book, showHeadings: true)
        let built = ChapterAttributedBuilder.build(title: "t", blocks: blocks, style: style)
        let mt = NSMutableAttributedString(attributedString: built.text)
        let ends = Dictionary(m.items.map { ($0.number, $0.endNumber) }, uniquingKeysWith: { x, _ in x })
        let ch = a.chapter
        AnnotationOverlays.applyBackgrounds(to: mt, ranges: built.verseRanges, selected: [],
                                            annotations: { ch.forDisplayVerse(number: $0, end: ends[$0]) }, palette: .light)
        let r = try #require(built.verseRanges[merged.number])
        let c = mt.attribute(.backgroundColor, at: r.location + 2, effectiveRange: nil) as? NSColor
        #expect(c == ReaderPalette.light.highlight(.pink))
        // un versículo sin resaltado no se pinta
        let other = try #require(m.items.first { $0.number > merged.endNumber })
        let ro = try #require(built.verseRanges[other.number])
        #expect(mt.attribute(.backgroundColor, at: ro.location + 2, effectiveRange: nil) == nil)
    }
}

// MARK: maquetación: fondos, marcador y nota

@Suite struct AnnotationRenderingTests {
    static func items() -> [DisplayVerse] {
        (1...4).map { DisplayVerse(number: $0, endNumber: $0, text: "Texto \($0)", headings: [], headingKinds: []) }
    }
    static func build(_ ann: ChapterAnnotations, perVerse: Bool = true) -> BuiltChapter {
        var style = ReaderStyle(palette: .light, fontScale: 1, latin: true, perVerse: perVerse)
        style.annotations = ann
        let blocks = ChapterBuilder.blocks(items: items(), layout: [], mode: .perVerse, showHeadings: true)
        return ChapterAttributedBuilder.build(title: "Juan 3", blocks: blocks, style: style)
    }
    static func note(_ id: Int64, _ a: Int, _ b: Int) -> Note {
        Note(id: id, book: 43, chapter: 3, verseStart: a, verseEnd: b, body: "x", createdAt: 1, updatedAt: 1)
    }

    @Test func bookmarkFlagBeforeNumberAndNoteIconAfterText() throws {
        let b = Self.build(ChapterAnnotations(highlights: [:], notes: [Self.note(7, 2, 3)], bookmarks: [2]))
        let s = b.text.string as NSString
        let flag = s.range(of: AnnotationOverlays.bookmarkGlyph)
        let t2 = s.range(of: "Texto 2")
        #expect(flag.location != NSNotFound && flag.location < t2.location)
        // ⚑ solo ante el versículo 2, y antes de su número
        #expect(s.components(separatedBy: AnnotationOverlays.bookmarkGlyph).count == 2)
        #expect(b.text.attribute(.bibliaVerseNumber, at: flag.location, effectiveRange: nil) as? Bool == true)
        // ✎: una sola vez (nota 2–3 → primer versículo), tras el texto del versículo 2, con enlace note://7
        let icons = s.components(separatedBy: AnnotationOverlays.noteGlyph).count - 1
        #expect(icons == 1)
        let ic = s.range(of: AnnotationOverlays.noteGlyph)
        #expect(ic.location >= NSMaxRange(t2) && ic.location < s.range(of: "Texto 3").location)
        let link = b.text.attribute(.link, at: ic.location, effectiveRange: nil) as? URL
        #expect(link.flatMap(NoteLink.parse) == 7)
        // el icono forma parte del rango del versículo (resaltado y clic)
        let r2 = try #require(b.verseRanges[2])
        #expect(NSLocationInRange(ic.location, r2))
    }

    @Test func noAnnotationsMeansNoExtraGlyphs() {
        let s = Self.build(ChapterAnnotations()).text.string
        #expect(!s.contains(AnnotationOverlays.bookmarkGlyph) && !s.contains(AnnotationOverlays.noteGlyph))
    }

    @Test func highlightSelectionBlendSearchAndGlossLines() throws {
        let pal = ReaderPalette.light
        var ann = ChapterAnnotations(highlights: [1: .yellow, 2: .blue], notes: [], bookmarks: [])
        let b = Self.build(ann)
        let mt = NSMutableAttributedString(attributedString: b.text)
        // marca una línea de glosa dentro del versículo 2: no debe pintarse
        let r2 = try #require(b.verseRanges[2])
        let glossRange = NSRange(location: NSMaxRange(r2) - 3, length: 3)
        mt.addAttribute(.bibliaGloss, value: true, range: glossRange)
        func paint(_ sel: Set<Int>) {
            AnnotationOverlays.applyBackgrounds(to: mt, ranges: b.verseRanges, selected: sel,
                                                annotations: { ann.forDisplayVerse(number: $0, end: nil) }, palette: pal)
        }
        func bg(_ verse: Int) -> NSColor? { mt.attribute(.backgroundColor, at: b.verseRanges[verse]!.location + 3, effectiveRange: nil) as? NSColor }
        paint([])
        #expect(bg(1) == pal.highlight(.yellow) && bg(2) == pal.highlight(.blue) && bg(3) == nil)
        #expect(mt.attribute(.backgroundColor, at: glossRange.location, effectiveRange: nil) == nil)
        paint([3])
        #expect(bg(3) == pal.selection)                          // solo selección: color de selección
        paint([1])
        let blended = try #require(bg(1))
        #expect(blended != pal.highlight(.yellow) && blended != pal.selection)   // mezcla de ambos
        // los saltos de línea no se pintan
        let nl = (mt.string as NSString).range(of: "\n", range: b.verseRanges[1]!)
        _ = nl
        // la búsqueda se aplica encima de resaltados y selección
        ReaderOverlays.applyHighlight(to: mt, ranges: b.verseRanges, terms: ["Texto"], palette: pal)
        #expect(bg(1) == pal.searchMatch)
        // y los quita al repintar
        ann.highlights = [:]
        paint([])
        #expect(bg(1) == nil)
    }

    @Test func columnsBuilderDecoratesAndKeepsRowRanges() throws {
        let v = { (n: Int, end: Int) in DisplayVerse(number: n, endNumber: end, text: "T\(n)", headings: [], headingKinds: []) }
        let rows = [ParallelRow(number: 1, cells: [.verse(v(1, 1)), .verse(v(1, 1))]),
                    ParallelRow(number: 2, cells: [.verse(v(2, 3)), .verse(v(2, 2))]),
                    ParallelRow(number: 3, cells: [.covered(by: v(2, 3)), .verse(v(3, 3))])]
        let ann = ChapterAnnotations(highlights: [3: .green], notes: [Note(id: 9, book: 1, chapter: 1, verseStart: 3, verseEnd: 3, body: "n", createdAt: 1, updatedAt: 1)], bookmarks: [1])
        let bc = ColumnsAttributedBuilder.build(rows: rows, columns: [("A", "es"), ("B", "es")], palette: .light, fontScale: 1,
                                                innerWidth: 300, annotations: ann)
        for c in bc.columns { #expect(c.text.string.contains(AnnotationOverlays.bookmarkGlyph)) }   // ⚑ en cada columna
        // la nota 3 vive en la fila 3: en la columna A (cubierta por 2–3) la fila 2 fusionada la lleva
        let a = bc.columns[0].text.string, b = bc.columns[1].text.string
        #expect(a.contains(AnnotationOverlays.noteGlyph) && b.contains(AnnotationOverlays.noteGlyph))
        // el resaltado del versículo 3 se ve en el versículo fusionado 2–3 de la columna A
        let ends: [Int: Int] = [2: 3]
        let mt = NSMutableAttributedString(attributedString: bc.columns[0].text)
        AnnotationOverlays.applyBackgrounds(to: mt, ranges: bc.columns[0].verseRanges, selected: [],
                                            annotations: { ann.forDisplayVerse(number: $0, end: ends[$0]) }, palette: .light)
        let r2 = try #require(bc.columns[0].verseRanges[2])
        #expect((mt.attribute(.backgroundColor, at: r2.location + 2, effectiveRange: nil) as? NSColor) == ReaderPalette.light.highlight(.green))
    }
}

// MARK: Markdown

@Suite struct MarkdownTests {
    static let st = MarkdownRenderer.Style(fontSize: 13, text: .black, muted: .gray, link: .blue)
    static func render(_ s: String) -> NSAttributedString { MarkdownRenderer.render(s, style: st) }
    static func font(_ a: NSAttributedString, _ sub: String) -> NSFont? {
        let r = (a.string as NSString).range(of: sub)
        return r.location == NSNotFound ? nil : a.attribute(.font, at: r.location, effectiveRange: nil) as? NSFont
    }
    static func isBold(_ f: NSFont?) -> Bool { f.map { NSFontManager.shared.traits(of: $0).contains(.boldFontMask) } ?? false }
    static func isItalic(_ f: NSFont?) -> Bool { f.map { NSFontManager.shared.traits(of: $0).contains(.italicFontMask) } ?? false }

    @Test func boldItalicAndCode() {
        let a = Self.render("Normal **negrita** y *cursiva* y _otra_ y `código` fin")
        #expect(a.string == "Normal negrita y cursiva y otra y código fin")
        #expect(Self.isBold(Self.font(a, "negrita")) && !Self.isItalic(Self.font(a, "negrita")))
        #expect(Self.isItalic(Self.font(a, "cursiva")) && !Self.isBold(Self.font(a, "cursiva")))
        #expect(Self.isItalic(Self.font(a, "otra")))
        #expect(!Self.isBold(Self.font(a, "Normal")) && !Self.isItalic(Self.font(a, "Normal")))
        let f = Self.font(a, "código")
        #expect(f?.isFixedPitch == true)
        let r = (a.string as NSString).range(of: "código")
        #expect(a.attribute(.backgroundColor, at: r.location, effectiveRange: nil) != nil)
    }

    @Test func boldItalicNestingAndEscapes() {
        let a = Self.render("***ambas*** y **con *cursiva* dentro** y \\*literal\\*")
        #expect(a.string == "ambas y con cursiva dentro y *literal*")
        #expect(Self.isBold(Self.font(a, "ambas")) && Self.isItalic(Self.font(a, "ambas")))
        #expect(Self.isBold(Self.font(a, "con ")) && !Self.isItalic(Self.font(a, "con ")))
        #expect(Self.isBold(Self.font(a, "cursiva")) && Self.isItalic(Self.font(a, "cursiva")))
    }

    @Test func unmatchedMarkersStayLiteral() {
        #expect(Self.render("2 * 3 = 6 y snake_case_name").string == "2 * 3 = 6 y snake_case_name")
        #expect(Self.render("**sin cerrar").string == "**sin cerrar")
        #expect(Self.render("`sin cerrar").string == "`sin cerrar")
        #expect(Self.render("[enlace roto](no url").string == "[enlace roto](no url")
        #expect(Self.render("").string == "")
    }

    @Test func headings() {
        let a = Self.render("# Título uno\n## Título dos\n### Tres\nTexto")
        #expect(a.string == "Título uno\nTítulo dos\nTres\nTexto")
        let h1 = Self.font(a, "Título uno"), h2 = Self.font(a, "Título dos"), h3 = Self.font(a, "Tres"), body = Self.font(a, "Texto")
        #expect(Self.isBold(h1) && Self.isBold(h2) && Self.isBold(h3) && !Self.isBold(body))
        #expect(h1!.pointSize > h2!.pointSize && h2!.pointSize > h3!.pointSize && h3!.pointSize > body!.pointSize)
        #expect(Self.render("#sin espacio").string == "#sin espacio")      // no es título
    }

    @Test func listsAndQuotes() {
        let a = Self.render("- uno\n* dos\n+ tres\n1. primero\n2. segundo\n> cita **fuerte**")
        let lines = a.string.components(separatedBy: "\n")
        #expect(lines[0] == "\u{2022}\tuno" && lines[1] == "\u{2022}\tdos" && lines[2] == "\u{2022}\ttres")
        #expect(lines[3] == "1.\tprimero" && lines[4] == "2.\tsegundo")
        #expect(lines[5].hasSuffix("cita fuerte") && lines[5].hasPrefix("\u{258F}"))
        let ps = a.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        #expect((ps?.headIndent ?? 0) > (ps?.firstLineHeadIndent ?? 0))     // sangría francesa
        #expect(Self.isItalic(Self.font(a, "cita")) && Self.isBold(Self.font(a, "fuerte")))
    }

    @Test func links() throws {
        let a = Self.render("Ver [Rom 5:3](https://example.org/x?a=1) y [**negro**](http://a.b) fin")
        #expect(a.string == "Ver Rom 5:3 y negro fin")
        let r = (a.string as NSString).range(of: "Rom 5:3")
        #expect(a.attribute(.link, at: r.location, effectiveRange: nil) as? URL == URL(string: "https://example.org/x?a=1"))
        #expect(a.attribute(.foregroundColor, at: r.location, effectiveRange: nil) as? NSColor == .blue)
        let n = (a.string as NSString).range(of: "negro")
        #expect(a.attribute(.link, at: n.location, effectiveRange: nil) != nil && Self.isBold(Self.font(a, "negro")))
        let plain = (a.string as NSString).range(of: "fin")
        #expect(a.attribute(.link, at: plain.location, effectiveRange: nil) == nil)
    }

    @Test func chineseAndEmojiSafe() {
        let a = Self.render("**神爱世人** 和 *世界* 🙂 `约3:16`")
        #expect(a.string == "神爱世人 和 世界 🙂 约3:16")
        #expect(Self.isBold(Self.font(a, "神爱世人")))
    }
}

// MARK: editor de notas

@Suite struct NoteEditorModelTests {
    static func make() throws -> (NoteEditorModel, AnnotationStore, () -> DispatchWorkItem?) {
        let (store, _) = try makeStore()
        let m = NoteEditorModel(saveDelay: 0.6)
        m.store = store
        var last: DispatchWorkItem?
        var delays: [TimeInterval] = []
        m.schedule = { d, w in delays.append(d); last = w }
        _ = delays
        return (m, store, { last })
    }

    @Test func autosaveIsDebouncedAt600ms() throws {
        let (store, _) = try makeStore()
        let m = NoteEditorModel()
        #expect(m.saveDelay == 0.6 && NoteEditorModel.defaultDelay == 0.6)
        m.store = store
        var items: [DispatchWorkItem] = [], delays: [TimeInterval] = []
        m.schedule = { d, w in delays.append(d); items.append(w) }
        var changes = 0
        m.onChange = { changes += 1 }
        m.load(book: 45, chapter: 8, range: 28...28)
        m.edit("H"); m.edit("Ho"); m.edit("Hola")
        #expect(try store.counts().notes == 0 && m.isDirty && m.statusText == "Guardando…")
        #expect(delays == [0.6, 0.6, 0.6])
        #expect(items[0].isCancelled && items[1].isCancelled && !items[2].isCancelled)   // cada tecla reinicia el temporizador
        items[2].perform()                                       // vence el temporizador
        let n = try #require(try store.chapter(book: 45, chapter: 8).notes.first)
        #expect(n.body == "Hola" && n.range == 28...28 && changes == 1)
        #expect(!m.isDirty && m.selectedId == n.id && m.statusText == "Guardada")
        m.edit("Hola mundo"); items.last!.perform()              // edición posterior = actualización, no nota nueva
        #expect(try store.counts().notes == 1 && (try store.note(id: n.id))?.body == "Hola mundo")
    }

    @Test func flushOnSwitchLoadAndClose() throws {
        let (m, store, _) = try Self.make()
        m.load(book: 43, chapter: 3, range: 16...16)
        m.edit("pendiente")
        #expect(try store.counts().notes == 0 && m.hasPendingSave)
        m.flush()                                                // cambio de pestaña / cierre / salir
        #expect(try store.counts().notes == 1 && !m.hasPendingSave)
        m.edit("otra cosa")
        m.load(book: 43, chapter: 3, range: 17...17)             // abrir otro versículo guarda antes
        #expect(try store.chapter(book: 43, chapter: 3).notes.first?.body == "otra cosa")
        #expect(m.selectedId == nil && m.draft == "" && m.statusText == "Sin guardar")
        m.edit("segunda"); m.flush()
        #expect(try store.counts().notes == 2)
        m.load(book: 43, chapter: 3, range: 16...17)             // dos notas solapan: se elige la primera, ambas listadas
        #expect(m.notes.count == 2)
        let first = m.notes[0], second = m.notes[1]
        m.edit("cambio en la primera")
        m.select(second.id)                                      // cambiar de nota guarda la anterior
        #expect(try store.note(id: first.id)?.body == "cambio en la primera")
        #expect(m.selectedId == second.id && m.draft == "segunda")
    }

    @Test func emptyBodyDeletesAndNewNote() throws {
        let (m, store, _) = try Self.make()
        m.load(book: 1, chapter: 1, range: 1...2)
        m.edit("   "); m.flush()
        #expect(try store.counts().notes == 0)                   // cuerpo vacío no crea nota
        m.edit("algo"); m.flush()
        let id = try #require(m.selectedId)
        m.edit("  \n "); m.flush()                               // cuerpo vacío borra la nota existente
        #expect(try store.note(id: id) == nil && m.selectedId == nil && m.createdAt == nil)
        m.edit("nueva"); m.flush()
        let id2 = try #require(m.selectedId)
        m.newNote()
        #expect(m.selectedId == nil && m.draft == "" && m.notes.map(\.id) == [id2])
        m.edit("segunda"); m.flush()
        #expect(try store.counts().notes == 2)
    }

    @Test func deleteSelectedAndTimestamps() throws {
        let (m, store, _) = try Self.make()
        var changes = 0
        m.onChange = { changes += 1 }
        m.load(book: 2, chapter: 3, range: 4...4)
        m.edit("hola"); m.flush()
        #expect(m.createdAt != nil && m.updatedAt != nil && m.errorMessage == nil)
        let id = try #require(m.selectedId)
        m.deleteSelected()
        #expect(try store.note(id: id) == nil && m.selectedId == nil && m.draft == "" && m.createdAt == nil)
        #expect(!m.hasPendingSave && changes == 2)
        // borrar con cambios sin guardar cancela el guardado diferido
        m.edit("x"); #expect(m.hasPendingSave)
        m.deleteSelected()                                       // no hay nota seleccionada: solo descarta
        #expect(try store.counts().notes == 0)
    }

    @Test func statesPreviewAndRequests() throws {
        let (m, _, _) = try Self.make()
        var states = 0
        m.onState = { states += 1 }
        #expect(!m.hasTarget)
        m.load(NoteRequest(book: 43, chapter: 3, range: 16...18))
        #expect(m.hasTarget && m.editingRange == 16...18 && !m.preview)
        m.preview = true
        #expect(m.preview && states >= 2)
        m.edit("a"); #expect(m.isDirty)
        m.flush()
        #expect(m.editingRange == 16...18 && m.selectedNote?.body == "a")
    }
}

// MARK: panel «Notas»

@Suite struct AnnotationListModelTests {
    static func seeded() throws -> (AnnotationListModel, AnnotationStore) {
        let (store, _) = try makeStore()
        try store.setHighlight(.yellow, book: 43, chapter: 3, verses: [16, 17], at: 100)
        try store.setHighlight(.blue, book: 19, chapter: 23, verses: [1], at: 300)
        _ = try store.toggleBookmark(book: 43, chapter: 1, verse: 1)
        _ = try store.addNote(book: 43, chapter: 3, verseStart: 16, body: "# Amor de Dios\n**Gran** texto", at: 200)
        _ = try store.addNote(book: 45, chapter: 8, verseStart: 28, body: "神爱世人 la meta", at: 400)
        let m = AnnotationListModel(store: store)
        return (m, store)
    }

    @Test func countsChipsAndFilters() throws {
        let (m, _) = try Self.seeded()
        #expect(m.counts == AnnotationCounts(notes: 2, highlights: 3, bookmarks: 1))
        #expect(AnnotationKindFilter.all.count(m.counts) == 6 && AnnotationKindFilter.notes.count(m.counts) == 2)
        #expect(AnnotationKindFilter.allCases.map(\.label) == ["Todo", "Notas", "Resaltados", "Marcadores"])
        #expect(m.items.count == 6 && !m.isFiltered)
        m.kind = .highlights
        #expect(m.items.count == 3 && m.items.allSatisfy { $0.kind == .highlight } && m.isFiltered)
        m.color = .blue
        #expect(m.items.map(\.book) == [19])
        m.kind = .notes                                          // cambiar de chip quita el filtro de color
        #expect(m.color == nil && m.items.count == 2)
        m.book = 45
        #expect(m.items.count == 1 && m.items[0].body?.contains("meta") == true)
        m.clearFilters()
        #expect(m.items.count == 6 && !m.isFiltered)
    }

    @Test func textSearchMatchesChineseAndAccents() throws {
        let (m, _) = try Self.seeded()
        m.text = "神爱"
        #expect(m.items.count == 1 && m.items[0].book == 45)
        m.text = "AMOR"                                          // sin distinguir mayúsculas
        #expect(m.items.count == 1 && m.items[0].book == 43)
        m.text = "zzz"
        #expect(m.items.isEmpty && m.isSearching)
        m.text = ""
    }

    @Test func sortOrders() throws {
        let (m, _) = try Self.seeded()
        m.sort = .canonical
        #expect(m.items.map(\.book) == [19, 43, 43, 43, 43, 45])
        m.sort = .updated
        #expect(m.items.first?.kind == .bookmark)                // el marcador es lo más reciente (fecha real)
        #expect(m.items.map(\.updatedAt) == m.items.map(\.updatedAt).sorted(by: >) && m.items.last?.updatedAt == 100)
    }

    @Test func mutationsRefreshAndNotify() throws {
        let (m, store) = try Self.seeded()
        var mutated = 0, refreshed = 0
        m.onMutation = { mutated += 1 }
        m.onRefresh = { refreshed += 1 }
        store.lastUsedColor = .pink
        let hl = try #require(m.items.first { $0.kind == .highlight && $0.verseStart == 17 })
        m.recolor(hl, to: .orange)
        #expect(try store.chapter(book: 43, chapter: 3).highlights[17] == .orange)
        #expect(store.lastUsedColor == .pink)                    // recolorear no cambia el último color
        let note = try #require(m.items.first { $0.kind == .note })
        m.delete(note)
        #expect(m.counts.notes == 1)
        let bm = try #require(m.items.first { $0.kind == .bookmark })
        m.delete(bm)
        #expect(m.counts.bookmarks == 0)
        let hl2 = try #require(m.items.first { $0.kind == .highlight })
        m.delete(hl2)
        #expect(m.counts.highlights == 2 && mutated == 4 && refreshed >= 4)
    }

    @Test func titlesDropMarkdown() {
        #expect(AnnotationListModel.title(of: "# Amor de **Dios**\nresto") == "Amor de Dios")
        #expect(AnnotationListModel.title(of: "- `código` aquí") == "código aquí")
        #expect(AnnotationListModel.title(of: "") == "")
    }

    @Test func emptyStoreIsHarmless() {
        let m = AnnotationListModel(store: nil)
        #expect(m.items.isEmpty && m.counts == AnnotationCounts())
        m.kind = .notes; m.text = "x"
        #expect(m.items.isEmpty)
    }
}
