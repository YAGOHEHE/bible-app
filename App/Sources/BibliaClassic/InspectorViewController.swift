import AppKit
import BibliaCore
import ClassicKit

/// Panel derecho (⌘I): pestañas Strong · Nota (L4) · Referencias.
final class InspectorViewController: NSViewController, NSTextViewDelegate {
    enum Tab: Int { case strong = 0, note = 1, refs = 2 }

    let model: ReaderModel
    private let settings: ClassicSettings
    private let tabs = NSSegmentedControl(labels: ["Strong", "Nota", "Referencias"], trackingMode: .selectOne, target: nil, action: nil)
    private let scroll = NSScrollView()
    private let text = NSTextView()
    private var palette = ReaderPalette.light
    private(set) var tab = Tab.strong
    private var strongModel: StrongInspectorModel?
    private var refsModel: RefsInspectorModel?
    private(set) var strongContent: StrongContent?
    private(set) var refsContent: RefsContent?
    private var refsSource: (book: Int, chapter: Int, verses: [Int])?
    private var refsLimit = CrossRefList.pageSize
    /// Navega a una referencia (referencia, versión opcional).
    var onNavigate: ((BibleRef, String?) -> Void)?

    init(model: ReaderModel, settings: ClassicSettings) {
        self.model = model; self.settings = settings
        super.init(nibName: nil, bundle: nil)
        if let db = model.bible {
            strongModel = StrongInspectorModel(lexicon: LexiconRepository(db: db))
            refsModel = RefsInspectorModel(repo: CrossRefRepository(db: db))
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) no se usa") }

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 600))
        tabs.segmentStyle = .rounded
        tabs.target = self
        tabs.action = #selector(tabPicked(_:))
        tabs.selectedSegment = 0
        tabs.setEnabled(false, forSegment: Tab.note.rawValue)       // la pestaña Nota llega en L4
        tabs.setToolTip("Las notas llegan en la siguiente versión", forSegment: Tab.note.rawValue)
        tabs.setAccessibilityLabel("Pestañas del inspector")
        tabs.translatesAutoresizingMaskIntoConstraints = false

        text.isEditable = false
        text.isSelectable = true
        text.isRichText = true
        text.drawsBackground = true
        text.isVerticallyResizable = true
        text.isHorizontallyResizable = false
        text.autoresizingMask = [.width]
        text.textContainerInset = NSSize(width: 14, height: 8)
        text.textContainer?.widthTracksTextView = true
        text.textContainer?.lineFragmentPadding = 0
        text.delegate = self
        text.linkTextAttributes = [.cursor: NSCursor.pointingHand]
        text.setAccessibilityLabel("Contenido del inspector")
        scroll.documentView = text
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(tabs)
        root.addSubview(scroll)
        NSLayoutConstraint.activate([
            tabs.topAnchor.constraint(equalTo: root.topAnchor, constant: 10),
            tabs.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 10),
            tabs.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -10),
            scroll.topAnchor.constraint(equalTo: tabs.bottomAnchor, constant: 8),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])
        view = root
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(themeChanged), name: .classicSettingsChanged, object: settings)
        nc.addObserver(self, selector: #selector(translationChanged), name: .classicTranslationChanged, object: model)
        applyPalette()
        render()
    }

    private func applyPalette() {
        palette = ReaderPalette.resolve(settings.theme)
        view.wantsLayer = true
        view.layer?.backgroundColor = palette.background.cgColor
        scroll.backgroundColor = palette.background
        text.backgroundColor = palette.background
        scroll.scrollerKnobStyle = palette.isDark ? .light : .default
        text.selectedTextAttributes = [.backgroundColor: palette.selection, .foregroundColor: palette.textPrimary]
    }

    @objc private func themeChanged() { applyPalette(); render() }
    @objc private func translationChanged() {
        if refsSource != nil { reloadRefs() }
        render()
    }
    @objc private func tabPicked(_ s: NSSegmentedControl) {
        tab = Tab(rawValue: s.selectedSegment) ?? .strong
        render()
    }

    func select(_ t: Tab) {
        tab = t
        tabs.selectedSegment = t.rawValue
        render()
    }

    // MARK: Strong

    func showStrong(_ sel: StrongSelection, translationId: String, word: String, length: Int) {
        let label = RefLabel.text(bookName: model.bookName(model.book, translation: translationId), chapter: model.chapter,
                                  from: sel.verse, to: sel.verse)
        strongContent = try? strongModel?.load(sel, word: word, verseText: model.verseText(translationId, verse: sel.verse),
                                               length: length, translationId: translationId, contextLabel: label)
        select(.strong)
        text.scrollToBeginningOfDocument(nil)
    }

    // MARK: Referencias

    func showRefs(book: Int, chapter: Int, verses: [Int]) {
        refsSource = (book, chapter, verses)
        refsLimit = CrossRefList.pageSize
        reloadRefs()
        select(.refs)
        text.scrollToBeginningOfDocument(nil)
    }

    private func reloadRefs() {
        guard let s = refsSource, let m = refsModel else { return }
        let m2 = model
        refsContent = try? m.load(book: s.book, chapter: s.chapter, verses: s.verses,
                                  bookName: { m2.bookName($0) }, text: { m2.text(of: $0) }, limit: refsLimit)
    }

    // MARK: pintar

    private func empty(_ title: String, _ body: String) -> NSAttributedString {
        let ps = NSMutableParagraphStyle(); ps.paragraphSpacing = 6; ps.paragraphSpacingBefore = 0
        let o = NSMutableAttributedString(string: title + "\n", attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold), .foregroundColor: palette.textPrimary, .paragraphStyle: ps])
        o.append(NSAttributedString(string: body, attributes: [
            .font: NSFont.systemFont(ofSize: 12), .foregroundColor: palette.textMuted]))
        return o
    }

    func render() {
        guard isViewLoaded, let st = text.textStorage else { return }
        let a: NSAttributedString
        switch tab {
        case .strong:
            if let c = strongContent {
                let m = model
                a = StrongTextBuilder.build(c, palette: palette, bookName: { m.bookName($0, translation: c.translationId) })
            } else {
                a = empty("Ninguna palabra seleccionada",
                          "Activa el modo Strong (⌥⌘S) en una versión con numeración Strong (KJV) y pulsa una palabra con subrayado punteado.")
            }
        case .note:
            a = empty("Notas", "Las notas llegan en la siguiente versión.")
        case .refs:
            if let c = refsContent {
                a = RefsTextBuilder.build(c, translationId: model.translationId, palette: palette)
            } else {
                a = empty("Referencias cruzadas",
                          "Coloca el cursor o selecciona texto en un versículo y elige «Referencias del versículo…» (⌥⌘R) del menú Ver.")
            }
        }
        st.setAttributedString(a)
    }

    // MARK: enlaces

    func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
        if InspectorLink.isMore(link) {
            refsLimit += CrossRefList.pageSize
            let y = scroll.contentView.bounds.minY
            reloadRefs(); render()
            scroll.contentView.scroll(to: NSPoint(x: 0, y: y))
            scroll.reflectScrolledClipView(scroll.contentView)
            return true
        }
        if let (ref, t) = InspectorLink.parse(link) { onNavigate?(ref, t); return true }
        return false
    }
}
