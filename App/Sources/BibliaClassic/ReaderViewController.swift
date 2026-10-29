import AppKit
import BibliaCore
import ClassicKit

/// NSTextView de solo lectura: ←/→ cambian de capítulo; ⌘= también aumenta el tamaño (teclados sin «+» directo).
final class ReaderTextView: NSTextView {
    var onPrev: (() -> Void)?
    var onNext: (() -> Void)?
    var onZoomIn: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        var mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        mods.subtract([.numericPad, .function])
        if mods.isEmpty {
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

/// S01: lector. NSTextView dentro de un NSScrollView con el capítulo como NSAttributedString.
final class ReaderViewController: NSViewController {
    let model: ReaderModel
    private let settings: ClassicSettings
    private let scrollView = NSScrollView()
    private let textView = ReaderTextView()
    private let messageLabel = NSTextField(labelWithString: "")
    private var built: BuiltChapter?
    private var palette = ReaderPalette.light
    private var suppressScroll = false
    private var lastWidth: CGFloat = 0
    private var messageTimer: Timer?
    private var flashTimer: Timer?

    init(model: ReaderModel, settings: ClassicSettings) {
        self.model = model; self.settings = settings
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
        textView.onPrev = { [weak self] in self?.model.goPrev() }
        textView.onNext = { [weak self] in self?.model.goNext() }
        textView.onZoomIn = { [weak self] in self?.settings.stepFont(1) }

        messageLabel.alignment = .center
        messageLabel.isHidden = true
        messageLabel.wantsLayer = true
        messageLabel.layer?.cornerRadius = 8
        messageLabel.maximumNumberOfLines = 3
        messageLabel.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin]

        root.addSubview(scrollView)
        root.addSubview(messageLabel)
        view = root

        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(chapterChanged(_:)), name: .classicChapterChanged, object: model)
        nc.addObserver(self, selector: #selector(settingsChanged), name: .classicSettingsChanged, object: settings)
        nc.addObserver(self, selector: #selector(scrolled), name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
        applyPalette()
    }

    var textViewForFocus: NSView { textView }

    // MARK: layout

    override func viewDidLayout() {
        super.viewDidLayout()
        let w = scrollView.contentSize.width
        guard abs(w - lastWidth) > 0.5 else { return }
        let first = lastWidth == 0
        lastWidth = w
        updateContainerWidth()
        if !first, built != nil { scrollToVerse(model.anchorVerse) }
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
        textView.backgroundColor = palette.background
        textView.selectedTextAttributes = [.backgroundColor: palette.selection, .foregroundColor: palette.textPrimary]
        scrollView.scrollerKnobStyle = palette.isDark ? .light : .default
        messageLabel.textColor = palette.textPrimary
        messageLabel.layer?.backgroundColor = palette.surface.cgColor
        messageLabel.layer?.borderColor = palette.border.cgColor
        messageLabel.layer?.borderWidth = 1
    }

    @objc private func settingsChanged() {
        updateAnchorFromScroll()
        applyPalette()
        render(scrollTo: model.anchorVerse)
    }

    @objc private func chapterChanged(_ n: Notification) {
        let v = n.userInfo?["scrollTo"] as? Int
        render(scrollTo: v)
        if let a = n.userInfo?["flashFrom"] as? Int, let b = n.userInfo?["flashTo"] as? Int { flash(a...b) }
    }

    /// Reconstruye el texto del capítulo actual y desplaza al versículo pedido (o al principio).
    func render(scrollTo verse: Int?) {
        view.layoutSubtreeIfNeeded()
        updateContainerWidth()
        flashTimer?.invalidate()
        guard let storage = textView.textStorage else { return }
        suppressScroll = true
        defer { suppressScroll = false }
        if model.items.isEmpty {
            built = nil
            let name = model.currentTranslation?.name ?? model.translationId
            let ps = NSMutableParagraphStyle(); ps.alignment = .center; ps.paragraphSpacing = 8
            let msg = NSMutableAttributedString()
            msg.append(NSAttributedString(string: "\n\nCapítulo no disponible\n", attributes: [
                .font: ReaderFonts.traits(ReaderFonts.latin(size: 22), bold: true), .foregroundColor: palette.textPrimary, .paragraphStyle: ps]))
            msg.append(NSAttributedString(string: "\(name) no incluye \(model.chapterTitle). Prueba con otra versión desde la barra de herramientas o navega a otro capítulo.", attributes: [
                .font: ReaderFonts.latin(size: 15), .foregroundColor: palette.textSecondary, .paragraphStyle: ps]))
            storage.setAttributedString(msg)
            return
        }
        let style = ReaderStyle(palette: palette, fontScale: settings.fontScale, latin: model.isLatin,
                                perVerse: settings.layout == .perLine)
        let b = ChapterAttributedBuilder.build(title: model.chapterTitle, blocks: model.blocks(), style: style)
        built = b
        storage.setAttributedString(b.text)
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        scrollToVerse(verse ?? 1)
    }

    // MARK: scrolling / anchor

    private func scrollToVerse(_ v: Int) {
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
        guard let b = built, let lm = textView.layoutManager else { return }
        var range: NSRange?
        for v in verses { if let r = b.verseRanges[v] { range = range.map { NSUnionRange($0, r) } ?? r } }
        guard let r = range else { return }
        flashTimer?.invalidate()
        let sel = palette.selection
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        lm.addTemporaryAttribute(.backgroundColor, value: sel, forCharacterRange: r)
        var step = 0
        let hold = reduce ? 3.0 : 2.0
        let start = Date()
        flashTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] t in
            guard let self = self, let lm = self.textView.layoutManager else { t.invalidate(); return }
            let el = Date().timeIntervalSince(start)
            if el < hold { return }
            if reduce || step >= 6 {
                lm.removeTemporaryAttribute(.backgroundColor, forCharacterRange: r)
                t.invalidate(); return
            }
            step += 1
            lm.addTemporaryAttribute(.backgroundColor, value: sel.withAlphaComponent(1 - CGFloat(step) / 6), forCharacterRange: r)
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

    /// ⌥⌘C: copia los versículos de la selección con su referencia.
    func copyWithReference() {
        guard let b = built else { return }
        let nums = Set(b.verses(intersecting: textView.selectedRange()))
        let vs = model.items.filter { nums.contains($0.number) }
        guard !vs.isEmpty else { NSSound.beep(); showMessage("Selecciona texto del capítulo para copiarlo con referencia."); return }
        let s = CopyFormatter.format(verses: vs, bookName: model.bookName(model.book, language: model.bookNameLanguage),
                                     chapter: model.chapter, translationId: model.translationId, language: model.language)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
        showMessage("Copiado con referencia")
    }

    func focusReader() { view.window?.makeFirstResponder(textView) }
}
