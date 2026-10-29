import AppKit
import BibliaCore
import ClassicKit

/// NSTextView de solo lectura: ←/→ cambian de capítulo; ⌘= también aumenta el tamaño (teclados sin «+» directo).
final class ReaderTextView: NSTextView {
    var onPrev: (() -> Void)?
    var onNext: (() -> Void)?
    var onZoomIn: (() -> Void)?
    /// Clic en un versículo (número o texto): (versículo, ⇧).
    var onVerseClick: ((Int, Bool) -> Void)?
    /// Menú contextual de un versículo (nil = fuera de un versículo).
    var menuProvider: ((Int?) -> NSMenu?)?
    /// Esc: devuelve true si lo atendió (vació la selección de versículos).
    var onEscape: (() -> Bool)?

    /// Versículo bajo el punto (coordenadas de la vista) y si está sobre un enlace (palabra Strong, icono de nota).
    func verseHit(at p: NSPoint) -> (verse: Int, isLink: Bool)? {
        guard let lm = layoutManager, let tc = textContainer, let st = textStorage, st.length > 0 else { return nil }
        let o = textContainerOrigin
        let pt = NSPoint(x: p.x - o.x, y: p.y - o.y)
        var frac: CGFloat = 0
        let g = lm.glyphIndex(for: pt, in: tc, fractionOfDistanceThroughGlyph: &frac)
        guard g < lm.numberOfGlyphs else { return nil }
        let used = lm.lineFragmentUsedRect(forGlyphAt: g, effectiveRange: nil)
        guard used.insetBy(dx: -2, dy: -1).contains(pt) else { return nil }
        let ci = lm.characterIndexForGlyph(at: g)
        guard ci < st.length, let v = st.attribute(.bibliaVerse, at: ci, effectiveRange: nil) as? Int else { return nil }
        return (v, st.attribute(.link, at: ci, effectiveRange: nil) != nil)
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        guard let hit = verseHit(at: p), !hit.isLink, onVerseClick != nil else { super.mouseDown(with: event); return }
        window?.makeFirstResponder(self)
        if event.modifierFlags.contains(.shift) { onVerseClick?(hit.verse, true); return }
        // El clic simple deja que NSTextView siga el arrastre (selección de texto, doble clic); si no se seleccionó
        // texto, es un clic en el versículo.
        super.mouseDown(with: event)
        if event.clickCount == 1, selectedRange().length == 0 { onVerseClick?(hit.verse, false) }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let p = convert(event.locationInWindow, from: nil)
        if let provider = menuProvider, let hit = verseHit(at: p), let m = provider(hit.verse) { return m }
        return super.menu(for: event)
    }

    override func keyDown(with event: NSEvent) {
        var mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        mods.subtract([.numericPad, .function])
        if mods.isEmpty {
            if event.keyCode == 53, onEscape?() == true { return }
            switch event.keyCode {
            case 123: onPrev?(); return
            case 124: onNext?(); return
            default: break
            }
        }
        super.keyDown(with: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        var mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        mods.subtract([.numericPad, .function])
        if mods == .command, event.charactersIgnoringModifiers == "=" { onZoomIn?(); return true }
        // ⌘← / ⌘→: alternativa a ⌘[ / ⌘] (en teclados como el español «[» necesita ⌥).
        if mods == .command, event.keyCode == 123 { onPrev?(); return true }
        if mods == .command, event.keyCode == 124 { onNext?(); return true }
        return super.performKeyEquivalent(with: event)
    }
}


/// Documento de las columnas: contiene un NSTextView por versión y pinta las líneas finas (filas y columnas).
final class ColumnsDocumentView: NSView {
    override var isFlipped: Bool { true }
    var rowTops: [CGFloat] = []
    var separatorXs: [CGFloat] = []
    var color = NSColor.gray
    var margin: CGFloat = 24

    override func draw(_ dirtyRect: NSRect) {
        color.setFill()
        for y in rowTops.dropFirst() {
            let r = NSRect(x: margin, y: y - 0.5, width: bounds.width - margin * 2, height: 1)
            if r.intersects(dirtyRect) { r.fill() }
        }
        for x in separatorXs {
            let r = NSRect(x: x - 0.5, y: 0, width: 1, height: bounds.height)
            if r.intersects(dirtyRect) { r.fill() }
        }
    }
}

/// Cabecera fija de columnas: sigla en el acento de la versión + idioma; línea fina debajo.
final class ColumnsHeaderView: NSView {
    static let height: CGFloat = 34
    private var infos: [(id: String, language: String)] = []
    private var palette = ReaderPalette.light
    var margin: CGFloat = 24

    func set(columns: [(id: String, language: String)], palette: ReaderPalette) {
        infos = columns; self.palette = palette
        setAccessibilityLabel("Columnas: " + columns.map { "\($0.id), \(languageLabel($0.language))" }.joined(separator: "; "))
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        palette.background.setFill(); bounds.fill()
        palette.border.setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: 1).fill()
        guard !infos.isEmpty else { return }
        let colW = (bounds.width - margin * 2) / CGFloat(infos.count)
        for (i, c) in infos.enumerated() {
            let x = margin + CGFloat(i) * colW + 14
            let sigla = NSAttributedString(string: c.id, attributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: .bold), .foregroundColor: palette.versionColor(i), .kern: 0.3])
            let lang = NSAttributedString(string: languageLabel(c.language), attributes: [
                .font: NSFont.systemFont(ofSize: 12), .foregroundColor: palette.textSecondary])
            let sy = (bounds.height - sigla.size().height) / 2 + 1
            sigla.draw(at: NSPoint(x: x, y: sy))
            lang.draw(at: NSPoint(x: x + sigla.size().width + 8, y: (bounds.height - lang.size().height) / 2 + 1))
        }
    }
}

/// S01: lector. NSTextView dentro de un NSScrollView con el capítulo como NSAttributedString.
final class ReaderViewController: NSViewController, NSTextViewDelegate {
    let model: ReaderModel
    let annotations: AnnotationsModel
    weak var commands: VerseCommands?
    private let settings: ClassicSettings
    private let bar = ActionBarView()
    private var structSig = ""
    private var primaryEnds: [Int: Int] = [:]
    private var columnEnds: [[Int: Int]] = []
    private let scrollView = NSScrollView()
    private let textView = ReaderTextView()
    private let messageLabel = NSTextField(labelWithString: "")
    private var built: BuiltChapter?
    private var palette = ReaderPalette.light
    private var suppressScroll = false
    private var lastWidth: CGFloat = 0
    private var messageTimer: Timer?
    private var flashTimer: Timer?
    // vista paralela
    private let colScroll = NSScrollView()
    private let colDoc = ColumnsDocumentView()
    private let colHeader = ColumnsHeaderView()
    private var colViews: [ReaderTextView] = []
    private var builtCols: BuiltColumns?
    private(set) var mode: ReaderMode = .single
    private var copyRows: [ParallelRow] = []
    private var copyColumns: [(id: String, language: String)] = []
    var onOpenVersions: (() -> Void)?
    /// Palabra Strong pulsada: (selección, versión, palabra, longitud).
    var onStrongClicked: ((StrongSelection, String, String, Int) -> Void)?
    /// Icono ✎ pulsado: abre esa nota.
    var onOpenNote: ((Int64) -> Void)?

    init(model: ReaderModel, settings: ClassicSettings, annotations: AnnotationsModel) {
        self.model = model; self.settings = settings; self.annotations = annotations
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) no se usa") }

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 760, height: 680))
        scrollView.frame = root.bounds
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.documentView = textView
        scrollView.contentView.postsBoundsChangedNotifications = true

        textView.frame = NSRect(x: 0, y: 0, width: 760, height: 680)
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.allowsUndo = false
        textView.usesFontPanel = false
        textView.drawsBackground = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.lineFragmentPadding = 0
        textView.setAccessibilityLabel("Texto bíblico")
        textView.delegate = self
        textView.onPrev = { [weak self] in self?.model.goPrev() }
        textView.onNext = { [weak self] in self?.model.goNext() }
        textView.onZoomIn = { [weak self] in self?.settings.stepFont(1) }
        wire(textView)

        messageLabel.alignment = .center
        messageLabel.isHidden = true
        messageLabel.wantsLayer = true
        messageLabel.layer?.cornerRadius = 8
        messageLabel.maximumNumberOfLines = 3
        messageLabel.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin]

        colScroll.hasVerticalScroller = true
        colScroll.autohidesScrollers = true
        colScroll.borderType = .noBorder
        colScroll.drawsBackground = true
        colScroll.documentView = colDoc
        colScroll.contentView.postsBoundsChangedNotifications = true
        colScroll.isHidden = true
        colHeader.isHidden = true

        root.addSubview(scrollView)
        root.addSubview(colScroll)
        root.addSubview(colHeader)
        root.addSubview(messageLabel)
        bar.isHidden = true
        bar.onAction = { [weak self] a in self?.commands?.perform(a, scope: nil) }
        bar.onHighlight = { [weak self] c in self?.commands?.highlight(c, scope: nil) }
        bar.onRemoveHighlight = { [weak self] in self?.commands?.removeHighlight(scope: nil) }
        bar.onClose = { [weak self] in self?.annotations.closeBar() }
        root.addSubview(bar)
        view = root

        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(chapterChanged(_:)), name: .classicChapterChanged, object: model)
        nc.addObserver(self, selector: #selector(settingsChanged), name: .classicSettingsChanged, object: settings)
        nc.addObserver(self, selector: #selector(scrolled), name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
        nc.addObserver(self, selector: #selector(scrolled), name: NSView.boundsDidChangeNotification, object: colScroll.contentView)
        nc.addObserver(self, selector: #selector(parallelChanged), name: .classicParallelChanged, object: model)
        nc.addObserver(self, selector: #selector(selectionChanged), name: .classicSelectionChanged, object: annotations)
        nc.addObserver(self, selector: #selector(annotationsChanged), name: .classicAnnotationsChanged, object: annotations)
        applyPalette()
    }

    /// Clic en versículos, menú contextual y Esc de una vista de texto del lector.
    private func wire(_ tv: ReaderTextView) {
        tv.onVerseClick = { [weak self] v, shift in self?.annotations.click(v, shift: shift) }
        tv.menuProvider = { [weak self] v in self?.commands?.contextMenu(forVerse: v) }
        tv.onEscape = { [weak self] in
            guard let a = self?.annotations, !a.selection.isEmpty || a.barVisible else { return false }
            a.clearSelection(); return true
        }
    }

    var textViewForFocus: NSView { mode == .columns ? (colViews.first ?? textView) : textView }

    // MARK: layout

    private func currentMode() -> ReaderMode {
        ParallelDecision.mode(on: model.parallel.on, layout: model.parallel.layout,
                              columnCount: model.columnIds.count, width: view.bounds.width)
    }

    private var barShown: Bool { annotations.barVisible && !annotations.selection.isEmpty }

    private func layoutFrames() {
        let full = view.bounds
        let barH = barShown ? bar.preferredHeight(width: full.width) : 0
        bar.frame = NSRect(x: 0, y: 0, width: full.width, height: barH)
        // La barra va dentro de la columna de lectura; el contenido recibe el hueco inferior para no quedar tapado.
        let b = NSRect(x: 0, y: barH, width: full.width, height: max(0, full.height - barH))
        if mode == .columns {
            colHeader.frame = NSRect(x: 0, y: full.height - ColumnsHeaderView.height, width: b.width, height: ColumnsHeaderView.height)
            colScroll.frame = NSRect(x: 0, y: barH, width: b.width, height: max(0, b.height - ColumnsHeaderView.height))
            scrollView.frame = b
        } else {
            scrollView.frame = b
            colScroll.frame = b
        }
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        layoutFrames()
        let w = view.bounds.width
        guard abs(w - lastWidth) > 0.5 else { return }
        let first = lastWidth == 0
        lastWidth = w
        updateContainerWidth()
        if first { return }
        if mode != currentMode() || mode == .columns {
            if built != nil || builtCols != nil || mode != currentMode() { render(scrollTo: model.anchorVerse) }
        } else if built != nil { scrollToVerse(model.anchorVerse) }
    }

    private func updateContainerWidth() {
        let w = scrollView.contentSize.width
        let cw = max(120, min(760, w - 48))
        textView.textContainer?.containerSize = NSSize(width: cw, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainerInset = NSSize(width: max(0, (w - cw) / 2), height: 28)
        if messageLabel.superview != nil {
            let mw = min(w - 40, 520)
            messageLabel.frame = NSRect(x: (view.bounds.width - mw) / 2, y: view.bounds.height - 56, width: mw, height: 36)
        }
    }

    // MARK: theme / render

    func applyPalette() {
        palette = ReaderPalette.resolve(settings.theme)
        scrollView.backgroundColor = palette.background
        colScroll.backgroundColor = palette.background
        colScroll.scrollerKnobStyle = palette.isDark ? .light : .default
        colDoc.color = palette.border
        textView.backgroundColor = palette.background
        textView.selectedTextAttributes = [.backgroundColor: palette.selection, .foregroundColor: palette.textPrimary]
        // Los enlaces del texto (palabras Strong, «Elegir glosas») llevan su propio color/subrayado.
        textView.linkTextAttributes = [.cursor: NSCursor.pointingHand]
        for tv in colViews { tv.linkTextAttributes = [.cursor: NSCursor.pointingHand] }
        scrollView.scrollerKnobStyle = palette.isDark ? .light : .default
        messageLabel.textColor = palette.textPrimary
        messageLabel.layer?.backgroundColor = palette.surface.cgColor
        messageLabel.layer?.borderColor = palette.border.cgColor
        messageLabel.layer?.borderWidth = 1
        if !bar.isHidden { bar.update(state: barState(), activeColor: annotations.highlightColor(), palette: palette) }
    }

    @objc private func settingsChanged() {
        updateAnchorFromScroll()
        applyPalette()
        render(scrollTo: model.anchorVerse)
    }

    private var pendingAnchor: Int?

    /// «Comparar»: activa la vista paralela y se queda en ese versículo.
    func compare(at verse: Int) {
        pendingAnchor = verse
        model.setParallel(on: true)
        pendingAnchor = nil
        flash(verse...verse)
    }

    @objc private func parallelChanged() {
        if let p = pendingAnchor { model.scrolled(toVerse: p) } else { updateAnchorFromScroll() }
        render(scrollTo: model.anchorVerse)
    }

    @objc private func chapterChanged(_ n: Notification) {
        let v = n.userInfo?["scrollTo"] as? Int
        render(scrollTo: v)
        if let a = n.userInfo?["flashFrom"] as? Int, let b = n.userInfo?["flashTo"] as? Int { flash(a...b) }
    }

    private func showMessagePage(_ storage: NSTextStorage) {
        built = nil; builtCols = nil
        let name = model.currentTranslation?.name ?? model.translationId
        let ps = NSMutableParagraphStyle(); ps.alignment = .center; ps.paragraphSpacing = 8
        let msg = NSMutableAttributedString()
        msg.append(NSAttributedString(string: "\n\nCapítulo no disponible\n", attributes: [
            .font: ReaderFonts.traits(ReaderFonts.latin(size: 22), bold: true), .foregroundColor: palette.textPrimary, .paragraphStyle: ps]))
        msg.append(NSAttributedString(string: "\(name) no incluye \(model.chapterTitle). Prueba con otra versión desde la barra de herramientas o navega a otro capítulo.", attributes: [
            .font: ReaderFonts.latin(size: 15), .foregroundColor: palette.textSecondary, .paragraphStyle: ps]))
        storage.setAttributedString(msg)
    }

    private func setColumnsVisible(_ on: Bool) {
        colScroll.isHidden = !on
        colHeader.isHidden = !on
        scrollView.isHidden = on
        layoutFrames()
    }

    /// Reconstruye el texto del capítulo actual y desplaza al versículo pedido (o al principio).
    func render(scrollTo verse: Int?) {
        let fr = view.window?.firstResponder
        let hadFocus = fr === textView || colViews.contains { $0 === fr } || fr == nil
        renderInner(scrollTo: verse)
        // Al cambiar de modo la vista enfocada se oculta y AppKit movería el foco a otro control.
        if hadFocus, view.window != nil { focusReader() }
    }

    private func renderInner(scrollTo verse: Int?) {
        view.layoutSubtreeIfNeeded()
        flashTimer?.invalidate()
        mode = currentMode()
        updateContainerWidth()
        if mode == .columns { renderColumns(scrollTo: verse); return }
        setColumnsVisible(false)
        builtCols = nil
        guard let storage = textView.textStorage else { return }
        suppressScroll = true
        defer { suppressScroll = false }
        var style = ReaderStyle(palette: palette, fontScale: settings.fontScale, latin: model.isLatin,
                                perVerse: settings.layout == .perLine)
        style.annotations = annotations.chapter
        structSig = Self.signature(style.annotations)
        primaryEnds = Dictionary(model.items.map { ($0.number, $0.endNumber) }, uniquingKeysWith: { a, _ in a })
        let b: BuiltChapter
        if mode == .glosses {
            let fallback = model.parallel.layout == .columns      // ventana estrecha: glosas = versiones activas
            let showGl = fallback || model.parallel.glossesOn
            let gids = fallback ? Array(model.columnIds.dropFirst()) : (showGl ? model.glossIds : [])
            let ids = [model.translationId] + gids
            let rows = model.rows(for: ids)
            if rows.isEmpty { showMessagePage(storage); return }
            copyRows = rows; copyColumns = model.columnInfos(ids)
            annotations.rows = rows.map(\.number); annotations.rowsAreExact = true
            let groups = GlossBuilder.groups(rows: rows, blocks: model.blocks(), columns: copyColumns, showGlosses: showGl)
            b = GlossAttributedBuilder.build(title: model.chapterTitle, groups: groups, style: style,
                                             notice: !fallback && model.parallel.glossesOn && model.glossIds.isEmpty)
        } else {
            if model.items.isEmpty { showMessagePage(storage); return }
            annotations.rows = model.items.map(\.number); annotations.rowsAreExact = false
            b = ChapterAttributedBuilder.build(title: model.chapterTitle, blocks: model.blocks(), style: style)
        }
        built = b
        storage.setAttributedString(b.text)
        applyOverlays(storage, built: b, id: model.translationId, strong: model.settings.strongMode, ends: primaryEnds)
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        scrollToVerse(verse ?? 1)
        updateBar(reveal: false)
    }

    private func renderColumns(scrollTo verse: Int?) {
        let ids = model.columnIds
        let rows = model.rows(for: ids)
        built = nil
        if rows.isEmpty {
            mode = .single
            setColumnsVisible(false)
            if let st = textView.textStorage { showMessagePage(st) }
            return
        }
        setColumnsVisible(true)
        suppressScroll = true
        defer { suppressScroll = false }
        let infos = model.columnInfos(ids)
        copyRows = rows; copyColumns = infos
        let W = colScroll.contentSize.width
        let n = CGFloat(infos.count)
        let colW = (W - 48) / n
        let inner = colW - 28
        let ann = annotations.chapter
        structSig = Self.signature(ann)
        annotations.rows = rows.map(\.number); annotations.rowsAreExact = true
        columnEnds = infos.indices.map { ci in
            var d: [Int: Int] = [:]
            for r in rows { if case .verse(let v)? = r.cells[safe: ci] { d[r.number] = v.endNumber } }
            return d
        }
        let bc = ColumnsAttributedBuilder.build(rows: rows, columns: infos, palette: palette, fontScale: settings.fontScale, innerWidth: inner, annotations: ann)
        builtCols = bc
        colHeader.set(columns: infos, palette: palette)
        colDoc.frame = NSRect(x: 0, y: 0, width: W, height: max(bc.totalHeight, colScroll.contentSize.height))
        colDoc.rowTops = bc.rowTops
        colDoc.separatorXs = (1..<max(1, infos.count)).map { 24 + CGFloat($0) * colW }
        while colViews.count > infos.count { colViews.removeLast().removeFromSuperview() }
        while colViews.count < infos.count {
            let tv = ReaderTextView()
            tv.isEditable = false; tv.isSelectable = true; tv.isRichText = true; tv.allowsUndo = false
            tv.usesFontPanel = false; tv.drawsBackground = false
            tv.isVerticallyResizable = false; tv.isHorizontallyResizable = false
            tv.textContainer?.widthTracksTextView = false
            tv.textContainer?.lineFragmentPadding = 0
            tv.textContainerInset = NSSize(width: 0, height: BuiltColumns.padTop)
            tv.delegate = self
            tv.linkTextAttributes = [.cursor: NSCursor.pointingHand]
            tv.onPrev = { [weak self] in self?.model.goPrev() }
            tv.onNext = { [weak self] in self?.model.goNext() }
            tv.onZoomIn = { [weak self] in self?.settings.stepFont(1) }
            wire(tv)
            colDoc.addSubview(tv)
            colViews.append(tv)
        }
        for (i, tv) in colViews.enumerated() {
            let c = bc.columns[i]
            tv.frame = NSRect(x: 24 + CGFloat(i) * colW + 14, y: 0, width: inner, height: bc.totalHeight)
            tv.textContainer?.containerSize = NSSize(width: inner, height: CGFloat.greatestFiniteMagnitude)
            tv.selectedTextAttributes = [.backgroundColor: palette.selection, .foregroundColor: palette.textPrimary]
            tv.setAccessibilityLabel("\(c.id), \(languageLabel(c.language))")
            tv.textStorage?.setAttributedString(c.text)
            if let st = tv.textStorage {
                applyOverlays(st, ranges: c.verseRanges, id: c.id, strong: model.settings.strongMode, ends: columnEnds[safe: i] ?? [:])
            }
            tv.setSelectedRange(NSRange(location: 0, length: 0))
        }
        colDoc.needsDisplay = true
        scrollToVerse(verse ?? 1)
        updateBar(reveal: false)
    }

    // MARK: overlays (Strong, resaltado de búsqueda)

    private func applyOverlays(_ storage: NSTextStorage, built b: BuiltChapter, id: String, strong: Bool, ends: [Int: Int]) {
        applyOverlays(storage, ranges: b.verseRanges, id: id, strong: strong, ends: ends)
    }

    private func applyOverlays(_ storage: NSTextStorage, ranges: [Int: NSRange], id: String, strong: Bool, ends: [Int: Int]) {
        if strong, model.hasStrongs(id) {
            ReaderOverlays.applyStrong(to: storage, ranges: ranges, spans: model.strongSpans(for: id),
                                       verseText: { [model] in model.verseText(id, verse: $0) }, palette: palette)
        }
        paintBackgrounds(storage, ranges: ranges, id: id, ends: ends)
    }

    /// Fondos: resaltados (por referencia, en cualquier versión), selección (mezclada) y, encima, búsqueda.
    private func paintBackgrounds(_ storage: NSTextStorage, ranges: [Int: NSRange], id: String, ends: [Int: Int]) {
        let ch = annotations.chapter
        AnnotationOverlays.applyBackgrounds(to: storage, ranges: ranges, selected: annotations.selectedRows,
                                            annotations: { ch.forDisplayVerse(number: $0, end: ends[$0]) }, palette: palette)
        if !model.highlightTerms.isEmpty, model.highlightTranslation == id {
            ReaderOverlays.applyHighlight(to: storage, ranges: ranges, terms: model.highlightTerms, palette: palette)
        }
    }

    /// Repinta resaltados y selección sin reconstruir el texto (no mueve el desplazamiento).
    private func refreshBackgrounds() {
        if mode == .columns {
            guard let bc = builtCols else { return }
            for (i, tv) in colViews.enumerated() {
                guard let st = tv.textStorage, let c = bc.columns[safe: i] else { continue }
                paintBackgrounds(st, ranges: c.verseRanges, id: c.id, ends: columnEnds[safe: i] ?? [:])
                tv.setNeedsDisplay(tv.bounds)
            }
        } else if let b = built, let st = textView.textStorage {
            paintBackgrounds(st, ranges: b.verseRanges, id: model.translationId, ends: primaryEnds)
            textView.setNeedsDisplay(textView.bounds)
        }
    }

    static func signature(_ a: ChapterAnnotations) -> String {
        "b" + a.bookmarks.sorted().map(String.init).joined(separator: ",")
            + "n" + a.notes.map { "\($0.id):\($0.verseStart)-\($0.verseEnd)" }.joined(separator: ",")
    }

    @objc private func selectionChanged() {
        refreshBackgrounds()
        updateBar(reveal: true)
    }

    @objc private func annotationsChanged() {
        if Self.signature(annotations.chapter) == structSig {
            refreshBackgrounds()
            updateBar(reveal: false)
        } else {
            rerenderKeepingScroll()
        }
    }

    private func rerenderKeepingScroll() {
        let clip = (mode == .columns ? colScroll : scrollView).contentView
        let y = clip.bounds.minY
        render(scrollTo: model.anchorVerse)
        let c2 = (mode == .columns ? colScroll : scrollView).contentView
        let doc = (mode == .columns ? colScroll.documentView : scrollView.documentView)?.frame.height ?? 0
        suppressScroll = true
        c2.scroll(to: NSPoint(x: 0, y: min(y, max(0, doc - c2.bounds.height))))
        (mode == .columns ? colScroll : scrollView).reflectScrolledClipView(c2)
        suppressScroll = false
    }

    // MARK: barra de acciones

    func barState() -> VerseMenuState {
        commands?.menuState(scope: nil) ?? VerseMenuState(context: VerseActionContext(selectedCount: annotations.selection.count))
    }

    private func updateBar(reveal: Bool) {
        let shown = barShown
        let was = !bar.isHidden
        let oldH = bar.frame.height
        bar.isHidden = !shown
        if shown { bar.update(state: barState(), activeColor: annotations.highlightColor(), palette: palette) }
        layoutFrames()
        bar.needsLayout = true
        if shown, reveal || !was || abs(oldH - bar.frame.height) > 0.5, let v = annotations.selection.anchor { ensureVisible(v) }
    }

    /// Desplaza lo justo para que el versículo quede a la vista sobre la barra.
    private func ensureVisible(_ v: Int) {
        suppressScroll = true
        defer { suppressScroll = false }
        if mode == .columns {
            guard let bc = builtCols, let i = bc.rowNumbers.firstIndex(of: v) else { return }
            colDoc.scrollToVisible(NSRect(x: 0, y: bc.rowTops[i], width: 1, height: bc.rowHeights[i]))
        } else if let r = built?.verseRanges[v] {
            textView.scrollRangeToVisible(NSRange(location: r.location, length: min(r.length, 1)))
            if let lm = textView.layoutManager, let tc = textView.textContainer, r.length > 0 {
                let g = lm.glyphIndexForCharacter(at: min(NSMaxRange(r) - 1, max(0, (built?.text.length ?? 1) - 1)))
                var rect = lm.lineFragmentRect(forGlyphAt: g, effectiveRange: nil)
                rect.origin.y += textView.textContainerOrigin.y
                _ = tc
                textView.scrollToVisible(rect)
            }
        }
    }

    /// Versículos (números de fila) bajo la selección de texto o el cursor; vacío si no hay ninguno.
    func currentVerses() -> [Int] {
        switch mode {
        case .columns:
            guard let bc = builtCols else { return [] }
            let sel = colViews.enumerated().map { (column: $0.offset, range: $0.element.selectedRange()) }
            let rows = bc.rows(intersecting: sel)
            if !rows.isEmpty { return rows.sorted() }
            for (i, tv) in colViews.enumerated() where view.window?.firstResponder === tv {
                let loc = tv.selectedRange().location
                if let hit = bc.columns[i].verseRanges.first(where: { NSLocationInRange(loc, $0.value) }) { return [hit.key] }
            }
            return []
        default:
            guard let b = built else { return [] }
            let r = textView.selectedRange()
            if r.length > 0 { return b.verses(intersecting: r) }
            guard b.text.length > 0, r.location < b.text.length else { return [] }
            if let hit = b.verseRanges.first(where: { NSLocationInRange(r.location, $0.value) }) { return [hit.key] }
            return []
        }
    }

    // MARK: scrolling / anchor

    private func scrollToVerse(_ v: Int) {
        if mode == .columns {
            guard let bc = builtCols else { return }
            suppressScroll = true
            defer { suppressScroll = false }
            let clip = colScroll.contentView
            let y = (v <= (bc.rowNumbers.first ?? 1)) ? 0 : (bc.top(ofRow: v) ?? 0)
            let maxY = max(0, colDoc.frame.height - clip.bounds.height)
            clip.scroll(to: NSPoint(x: 0, y: min(max(0, y), maxY)))
            colScroll.reflectScrolledClipView(clip)
            return
        }
        guard let b = built, let lm = textView.layoutManager, let tc = textView.textContainer else { return }
        suppressScroll = true
        defer { suppressScroll = false }
        lm.ensureLayout(for: tc)
        // El marco del NSTextView se ajusta de forma diferida: fijarlo ya para poder desplazarse de inmediato.
        let docH = lm.usedRect(for: tc).maxY + textView.textContainerInset.height * 2
        textView.setFrameSize(NSSize(width: textView.frame.width, height: max(docH, scrollView.contentSize.height)))
        let loc = b.scrollTargets[v] ?? 0
        var y: CGFloat = 0
        if loc > 0, b.text.length > 0 {
            let g = lm.glyphIndexForCharacter(at: min(loc, b.text.length - 1))
            y = lm.lineFragmentRect(forGlyphAt: g, effectiveRange: nil).minY + textView.textContainerOrigin.y - 8
        }
        let clip = scrollView.contentView
        let maxY = max(0, (scrollView.documentView?.frame.height ?? 0) - clip.bounds.height)
        clip.scroll(to: NSPoint(x: 0, y: min(max(0, y), maxY)))
        scrollView.reflectScrolledClipView(clip)
    }

    private func topVerse() -> Int? {
        if mode == .columns { return builtCols?.row(atY: colScroll.contentView.bounds.minY + 12) }
        guard let b = built, let lm = textView.layoutManager, let tc = textView.textContainer else { return nil }
        let origin = textView.textContainerOrigin
        let p = NSPoint(x: textView.bounds.midX - origin.x, y: scrollView.contentView.bounds.minY + 12 - origin.y)
        let idx = lm.characterIndex(for: p, in: tc, fractionOfDistanceBetweenInsertionPoints: nil)
        guard b.text.length > 0 else { return nil }
        var glyphRange = NSRange()
        let g = lm.glyphIndexForCharacter(at: min(idx, b.text.length - 1))
        _ = lm.lineFragmentRect(forGlyphAt: g, effectiveRange: &glyphRange)
        let line = lm.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        return b.verse(forLine: line)
    }

    private func updateAnchorFromScroll() {
        if let v = topVerse() { model.scrolled(toVerse: v) }
    }

    @objc private func scrolled() {
        guard !suppressScroll else { return }
        updateAnchorFromScroll()
    }

    // MARK: flash (ir a)

    private func flash(_ verses: ClosedRange<Int>) {
        var targets: [(NSLayoutManager, NSRange)] = []
        if mode == .columns {
            guard let bc = builtCols else { return }
            for (i, tv) in colViews.enumerated() {
                var range: NSRange?
                for v in verses { if let r = bc.columns[i].verseRanges[v] { range = range.map { NSUnionRange($0, r) } ?? r } }
                if let r = range, let lm = tv.layoutManager { targets.append((lm, r)) }
            }
        } else {
            guard let b = built, let lm = textView.layoutManager else { return }
            var range: NSRange?
            for v in verses { if let r = b.verseRanges[v] { range = range.map { NSUnionRange($0, r) } ?? r } }
            if let r = range { targets.append((lm, r)) }
        }
        guard !targets.isEmpty else { return }
        flashTimer?.invalidate()
        let sel = palette.selection
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        for (lm, r) in targets { lm.addTemporaryAttribute(.backgroundColor, value: sel, forCharacterRange: r) }
        var step = 0
        let hold = reduce ? 3.0 : 2.0
        let start = Date()
        flashTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { t in
            let el = Date().timeIntervalSince(start)
            if el < hold { return }
            if reduce || step >= 6 {
                for (lm, r) in targets { lm.removeTemporaryAttribute(.backgroundColor, forCharacterRange: r) }
                t.invalidate(); return
            }
            step += 1
            for (lm, r) in targets { lm.addTemporaryAttribute(.backgroundColor, value: sel.withAlphaComponent(1 - CGFloat(step) / 6), forCharacterRange: r) }
        }
    }

    // MARK: messages / copy

    func showMessage(_ text: String) {
        messageTimer?.invalidate()
        if messageLabel.superview == nil { view.addSubview(messageLabel) }
        messageLabel.stringValue = text
        messageLabel.isHidden = false
        updateContainerWidth()
        messageTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: false) { [weak self] _ in
            self?.messageLabel.isHidden = true
        }
    }

    func hideMessage() { messageTimer?.invalidate(); messageLabel.isHidden = true }

    /// Filas tocadas por la selección de TEXTO (arrastre del ratón) o por el cursor; vacío si no hay.
    private func textSelectionRows() -> Set<Int> {
        switch mode {
        case .single, .glosses:
            guard let b = built else { return [] }
            return Set(b.verses(intersecting: textView.selectedRange()))
        case .columns:
            guard let bc = builtCols else { return [] }
            return bc.rows(intersecting: colViews.enumerated().map { (column: $0.offset, range: $0.element.selectedRange()) })
        }
    }

    /// Hay texto seleccionado con el ratón en alguna vista del lector.
    var hasTextSelection: Bool {
        mode == .columns ? colViews.contains { $0.selectedRange().length > 0 } : textView.selectedRange().length > 0
    }

    /// Texto de los versículos `selected` (filas): con o sin referencia. En paralela, una línea por versión visible.
    func verseCopyText(rows selected: Set<Int>, reference: Bool) -> String? {
        guard !selected.isEmpty else { return nil }
        let names: (Int, String) -> String = { [model] n, lang in model.bookName(n, language: lang) }
        let cols = copyColumns.map { (id: $0.id, language: $0.language) }
        switch mode {
        case .single:
            let vs = model.items.filter { selected.contains($0.number) }
            guard !vs.isEmpty else { return nil }
            return reference
                ? CopyFormatter.format(verses: vs, bookName: model.bookName(model.book, language: model.bookNameLanguage),
                                       chapter: model.chapter, translationId: model.translationId, language: model.language)
                : PlainCopy.text(verses: vs, language: model.language)
        case .glosses:
            return reference
                ? GlossBuilder.copyText(rows: copyRows, selected: selected, book: model.book, chapter: model.chapter,
                                        columns: copyColumns, showGlosses: true, bookName: names)
                : PlainCopy.text(rows: copyRows, selected: selected, columns: cols)
        case .columns:
            return reference
                ? ParallelCopy.format(rows: copyRows, selected: selected, book: model.book, chapter: model.chapter,
                                      columns: copyColumns, bookName: names)
                : PlainCopy.text(rows: copyRows, selected: selected, columns: cols)
        }
    }

    /// Copia al portapapeles los versículos del ámbito (selección, o el del clic derecho).
    func copyVerses(scope: Set<Int>?, reference: Bool) {
        var sel = scope ?? annotations.selectedRows
        if sel.isEmpty { sel = textSelectionRows() }          // ⌥⌘C sin versículos marcados: la selección de texto
        guard let s = verseCopyText(rows: sel, reference: reference), !s.isEmpty else {
            NSSound.beep(); showMessage("Selecciona uno o más versículos (clic en ellos) para copiarlos."); return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
        showMessage(reference ? "Copiado con referencia" : "Copiado")
    }

    /// ⌥⌘C: copia los versículos seleccionados con su referencia (en paralela, una línea por versión visible).
    func copyWithReference() { copyVerses(scope: nil, reference: true) }

    /// Versículo que se debe ver al abrir una nota: lo hace la ventana principal.
    func flashVerses(_ verses: ClosedRange<Int>) { flash(verses) }

    // MARK: NSTextViewDelegate

    func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
        if "\(link)" == "biblia://glosas" { onOpenVersions?(); return true }
        let url = (link as? URL) ?? URL(string: "\(link)")
        if let u = url, let id = NoteLink.parse(u) { onOpenNote?(id); return true }
        if let u = url, let sel = StrongLink.parse(u) {
            let id: String
            if let i = colViews.firstIndex(where: { $0 === textView }), let c = builtCols?.columns[safe: i] { id = c.id }
            else { id = model.translationId }
            let ns = textView.textStorage?.string as NSString?
            var word = sel.strong, len = 0
            if let st = textView.textStorage, charIndex < st.length {
                var eff = NSRange()
                if st.attribute(.link, at: charIndex, effectiveRange: &eff) != nil, let t = ns { word = t.substring(with: eff); len = eff.length }
            }
            if let sp = model.strongSpans(for: id)[sel.verse]?.first(where: { $0.start == sel.start && $0.strong == sel.strong }) { len = sp.length }
            onStrongClicked?(sel, id, word, len)
            return true
        }
        return false
    }

    private var clearingSelection = false
    func textViewDidChangeSelection(_ notification: Notification) {
        guard !clearingSelection, mode == .columns, let tv = notification.object as? NSTextView,
              tv.selectedRange().length > 0 else { return }
        clearingSelection = true
        for other in colViews where other !== tv { other.setSelectedRange(NSRange(location: 0, length: 0)) }
        clearingSelection = false
    }

    func focusReader() { view.window?.makeFirstResponder(textViewForFocus) }
}
