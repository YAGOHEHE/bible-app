import AppKit
import BibliaCore
import ClassicKit

private final class SidebarItem: NSObject {
    let title: String?       // grupo
    let book: Int            // libro (0 = grupo)
    var children: [SidebarItem] = []
    init(title: String) { self.title = title; self.book = 0 }
    init(book: Int) { self.title = nil; self.book = book }
    var isGroup: Bool { book == 0 }
}

private final class ThemedRowView: NSTableRowView {
    var fill = NSColor.selectedContentBackgroundColorCompat
    override func drawSelection(in dirtyRect: NSRect) {
        guard isSelected else { return }
        fill.setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 4, dy: 1), xRadius: 5, yRadius: 5).fill()
    }
    override var isEmphasized: Bool { get { true } set {} }
}

extension NSColor {
    /// `selectedContentBackgroundColor` es 10.14+: alternativa para 10.13.
    static var selectedContentBackgroundColorCompat: NSColor {
        if #available(macOS 10.14, *) { return NSColor.selectedContentBackgroundColor }
        return NSColor.alternateSelectedControlColor
    }
}

/// Cuadrícula de capítulos del libro seleccionado (botones, accesibles).
private final class ChapterGridView: NSView {
    override var isFlipped: Bool { true }
    var onSelect: ((Int) -> Void)?
    private var buttons: [NSButton] = []
    private var palette = ReaderPalette.light
    private var current = 0
    private let cell = NSSize(width: 36, height: 26), gap: CGFloat = 4, margin: CGFloat = 10

    func configure(count: Int, current: Int, palette: ReaderPalette) {
        self.palette = palette; self.current = current
        if buttons.count != count {
            buttons.forEach { $0.removeFromSuperview() }
            buttons = (0..<count).map { i in
                let b = NSButton(frame: .zero)
                b.isBordered = false
                b.wantsLayer = true
                b.layer?.cornerRadius = 5
                b.tag = i + 1
                b.target = self
                b.action = #selector(tap(_:))
                b.setAccessibilityLabel("Capítulo \(i + 1)")
                addSubview(b)
                return b
            }
        }
        for b in buttons { style(b) }
        needsLayout = true
        layoutButtons(width: frame.width)
    }

    private func style(_ b: NSButton) {
        let sel = b.tag == current
        let ps = NSMutableParagraphStyle(); ps.alignment = .center
        b.attributedTitle = NSAttributedString(string: "\(b.tag)", attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: sel ? .semibold : .regular),
            .foregroundColor: sel ? (palette.isDark ? ReaderPalette.hex(0x10163A) : NSColor.white) : palette.textPrimary,
            .paragraphStyle: ps])
        b.layer?.backgroundColor = (sel ? palette.accent : palette.background).cgColor
        b.layer?.borderWidth = sel ? 0 : 1
        b.layer?.borderColor = palette.border.cgColor
    }

    @objc private func tap(_ b: NSButton) { onSelect?(b.tag) }

    private func layoutButtons(width: CGFloat) {
        let cols = max(1, Int((width - 2 * margin + gap) / (cell.width + gap)))
        for (i, b) in buttons.enumerated() {
            let r = i / cols, c = i % cols
            b.frame = NSRect(x: margin + CGFloat(c) * (cell.width + gap), y: margin + CGFloat(r) * (cell.height + gap),
                             width: cell.width, height: cell.height)
        }
        let rows = (buttons.count + cols - 1) / cols
        let h = margin * 2 + CGFloat(rows) * (cell.height + gap)
        if abs(frame.height - h) > 0.5 { setFrameSize(NSSize(width: frame.width, height: h)) }
    }

    override func layout() { super.layout(); layoutButtons(width: bounds.width) }
}

/// S02: barra lateral — Recientes, Antiguo/Nuevo Testamento, filtro y cuadrícula de capítulos.
final class SidebarViewController: NSViewController, NSOutlineViewDataSource, NSOutlineViewDelegate, NSSearchFieldDelegate {
    private let model: ReaderModel
    private let settings: ClassicSettings
    private let outline = NSOutlineView()
    private let filter = NSSearchField()
    private let gridTitle = NSTextField(labelWithString: "")
    private let grid = ChapterGridView()
    private let gridScroll = NSScrollView()
    private let outlineScroll = NSScrollView()
    private let separator = NSBox()
    private var groups: [SidebarItem] = []
    private var palette = ReaderPalette.light
    private var suppress = false
    private var gridBook = 0
    private let modeSegment = NSSegmentedControl(labels: ["Libros", "Buscar", "Notas"], trackingMode: .selectOne, target: nil, action: nil)
    let searchVC: SearchViewController
    let notesVC: NotesPanelViewController
    enum Mode: Int { case books = 0, search = 1, notes = 2 }
    private(set) var mode = Mode.books
    var onModeChanged: ((Mode) -> Void)?

    init(model: ReaderModel, settings: ClassicSettings, annotations: AnnotationsModel) {
        self.model = model; self.settings = settings
        searchVC = SearchViewController(model: model, settings: settings)
        notesVC = NotesPanelViewController(model: model, annotations: annotations, settings: settings)
        super.init(nibName: nil, bundle: nil)
        addChild(searchVC)
        addChild(notesVC)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) no se usa") }

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 230, height: 680))
        root.wantsLayer = true

        filter.placeholderString = "Filtrar libros"
        filter.delegate = self
        filter.setAccessibilityLabel("Filtrar libros")
        filter.translatesAutoresizingMaskIntoConstraints = false

        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("book"))
        outline.addTableColumn(col)
        outline.outlineTableColumn = col
        outline.headerView = nil
        outline.rowHeight = 24
        outline.indentationPerLevel = 10
        outline.selectionHighlightStyle = .regular
        outline.dataSource = self
        outline.delegate = self
        outline.setAccessibilityLabel("Libros")
        outline.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        outlineScroll.documentView = outline
        outlineScroll.hasVerticalScroller = true
        outlineScroll.autohidesScrollers = true
        outlineScroll.drawsBackground = false
        outlineScroll.translatesAutoresizingMaskIntoConstraints = false

        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false

        gridTitle.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        gridTitle.translatesAutoresizingMaskIntoConstraints = false
        grid.frame = NSRect(x: 0, y: 0, width: 210, height: 100)
        grid.onSelect = { [weak self] c in
            guard let s = self else { return }
            s.model.jump(book: s.gridBook, chapter: c)
        }
        gridScroll.documentView = grid
        gridScroll.hasVerticalScroller = true
        gridScroll.autohidesScrollers = true
        gridScroll.drawsBackground = false
        gridScroll.translatesAutoresizingMaskIntoConstraints = false

        modeSegment.segmentStyle = .rounded
        modeSegment.target = self
        modeSegment.action = #selector(modePicked(_:))
        modeSegment.selectedSegment = 0
        modeSegment.setAccessibilityLabel("Panel de la barra lateral")
        modeSegment.translatesAutoresizingMaskIntoConstraints = false
        let sv = searchVC.view
        sv.translatesAutoresizingMaskIntoConstraints = false
        sv.isHidden = true
        let nv = notesVC.view
        nv.translatesAutoresizingMaskIntoConstraints = false
        nv.isHidden = true
        for v in [modeSegment, filter, outlineScroll, separator, gridTitle, gridScroll, sv, nv] as [NSView] { root.addSubview(v) }
        NSLayoutConstraint.activate([
            modeSegment.topAnchor.constraint(equalTo: root.topAnchor, constant: 10),
            modeSegment.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 10),
            modeSegment.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -10),
            sv.topAnchor.constraint(equalTo: modeSegment.bottomAnchor, constant: 8),
            sv.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            sv.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            sv.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            nv.topAnchor.constraint(equalTo: modeSegment.bottomAnchor, constant: 8),
            nv.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            nv.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            nv.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            filter.topAnchor.constraint(equalTo: modeSegment.bottomAnchor, constant: 8),
            filter.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 10),
            filter.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -10),
            outlineScroll.topAnchor.constraint(equalTo: filter.bottomAnchor, constant: 8),
            outlineScroll.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            outlineScroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            separator.topAnchor.constraint(equalTo: outlineScroll.bottomAnchor),
            separator.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            gridTitle.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 8),
            gridTitle.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            gridTitle.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
            gridScroll.topAnchor.constraint(equalTo: gridTitle.bottomAnchor, constant: 2),
            gridScroll.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            gridScroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            gridScroll.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            gridScroll.heightAnchor.constraint(equalToConstant: 170),
        ])
        view = root

        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(chapterChanged), name: .classicChapterChanged, object: model)
        nc.addObserver(self, selector: #selector(translationChanged), name: .classicTranslationChanged, object: model)
        nc.addObserver(self, selector: #selector(recentsChanged), name: .classicRecentsChanged, object: model)
        nc.addObserver(self, selector: #selector(themeChanged), name: .classicSettingsChanged, object: settings)
        applyPalette()
        rebuild()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        grid.setFrameSize(NSSize(width: gridScroll.contentSize.width, height: grid.frame.height))
        grid.needsLayout = true
    }

    // MARK: theme

    private func applyPalette() {
        palette = ReaderPalette.resolve(settings.theme)
        view.layer?.backgroundColor = palette.surface.cgColor
        outline.backgroundColor = palette.surface
        gridTitle.textColor = palette.textMuted
        outlineScroll.scrollerKnobStyle = palette.isDark ? .light : .default
        gridScroll.scrollerKnobStyle = palette.isDark ? .light : .default
    }

    @objc private func themeChanged() {
        applyPalette()
        outline.reloadData()
        selectCurrentBook()
        refreshGrid()
    }

    // MARK: data

    private func matches(_ book: Int, _ f: String) -> Bool {
        if model.bookName(book).range(of: f, options: [.caseInsensitive, .diacriticInsensitive]) != nil { return true }
        if let b = try? ReferenceParser.resolveBook(f), b == book { return true }
        return BookNameLanguage.name(book, language: "en").range(of: f, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    private func rebuild() {
        let f = filter.stringValue.trimmingCharacters(in: .whitespaces)
        func items(_ r: ClosedRange<Int>) -> [SidebarItem] { r.filter { f.isEmpty || matches($0, f) }.map { SidebarItem(book: $0) } }
        var g: [SidebarItem] = []
        if f.isEmpty, !model.recents.isEmpty {
            let r = SidebarItem(title: "Recientes"); r.children = model.recents.map { SidebarItem(book: $0) }; g.append(r)
        }
        let ot = SidebarItem(title: "Antiguo Testamento"); ot.children = items(1...39)
        let nt = SidebarItem(title: "Nuevo Testamento"); nt.children = items(40...66)
        for x in [ot, nt] where !x.children.isEmpty { g.append(x) }
        groups = g
        suppress = true
        outline.reloadData()
        for x in groups { outline.expandItem(x) }
        suppress = false
        selectCurrentBook()
    }

    private func selectCurrentBook() {
        suppress = true
        defer { suppress = false }
        // Preferimos la fila del testamento (no la de Recientes) para que la selección no salte al reordenar.
        for x in groups.reversed() where x.title != "Recientes" {
            if let it = x.children.first(where: { $0.book == model.book }) {
                let row = outline.row(forItem: it)
                if row >= 0 { outline.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false); outline.scrollRowToVisible(row) }
                return
            }
        }
        outline.deselectAll(nil)
    }

    private func refreshGrid() {
        gridBook = model.book
        let count = model.chapterCounts[safe: model.book - 1] ?? 0
        gridTitle.stringValue = "CAPÍTULOS · \(model.bookName(model.book)) (\(count))".uppercased()
        grid.setFrameSize(NSSize(width: gridScroll.contentSize.width, height: grid.frame.height))
        grid.configure(count: count, current: model.chapter, palette: palette)
        grid.scroll(NSPoint(x: 0, y: 0))
        if let b = grid.subviews.compactMap({ $0 as? NSButton }).first(where: { $0.tag == model.chapter }) {
            grid.scrollToVisible(b.frame)
        }
    }

    @objc private func chapterChanged() { selectCurrentBook(); refreshGrid() }
    @objc private func translationChanged() { outline.reloadData(); for x in groups { outline.expandItem(x) }; selectCurrentBook(); refreshGrid() }
    @objc private func recentsChanged() {
        // Reconstruir Recientes sin mover la selección del usuario.
        if filter.stringValue.isEmpty { rebuild() }
    }

    func focusFilter() { setMode(.books); view.window?.makeFirstResponder(filter) }

    @objc private func modePicked(_ s: NSSegmentedControl) { setMode(Mode(rawValue: s.selectedSegment) ?? .books) }

    func setMode(_ m: Mode) {
        guard m != mode || modeSegment.selectedSegment != m.rawValue else { return }
        mode = m
        modeSegment.selectedSegment = m.rawValue
        let books = m == .books
        for v in [filter, outlineScroll, separator, gridTitle, gridScroll] as [NSView] { v.isHidden = !books }
        searchVC.view.isHidden = m != .search
        notesVC.view.isHidden = m != .notes
        if m == .notes { notesVC.refresh() }
        onModeChanged?(m)
    }

    /// ⌘F: muestra el panel «Buscar» y enfoca el campo.
    func showSearch(prefill: String? = nil) {
        setMode(.search)
        if let p = prefill, !p.isEmpty { searchVC.run(p) }
        searchVC.focusField()
    }

    func controlTextDidChange(_ obj: Notification) { rebuild() }

    // MARK: NSOutlineView

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        guard let i = item as? SidebarItem else { return groups.count }
        return i.children.count
    }
    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        guard let i = item as? SidebarItem else { return groups[index] }
        return i.children[index]
    }
    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool { (item as? SidebarItem)?.isGroup ?? false }
    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool { !((item as? SidebarItem)?.isGroup ?? true) }

    func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
        let r = ThemedRowView()
        r.fill = palette.selection
        return r
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let it = item as? SidebarItem else { return nil }
        let id = NSUserInterfaceItemIdentifier("cell")
        let cell: NSTableCellView
        if let c = outlineView.makeView(withIdentifier: id, owner: self) as? NSTableCellView { cell = c } else {
            cell = NSTableCellView()
            cell.identifier = id
            let tf = NSTextField(labelWithString: "")
            tf.translatesAutoresizingMaskIntoConstraints = false
            tf.lineBreakMode = .byTruncatingTail
            cell.addSubview(tf)
            cell.textField = tf
            NSLayoutConstraint.activate([
                tf.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                tf.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                tf.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
        }
        let tf = cell.textField!
        if it.isGroup {
            tf.stringValue = (it.title ?? "").uppercased()
            tf.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
            tf.textColor = palette.textMuted
        } else {
            tf.stringValue = model.bookName(it.book)
            tf.font = NSFont.systemFont(ofSize: 13)
            tf.textColor = palette.textPrimary
        }
        return cell
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard !suppress else { return }
        let row = outline.selectedRow
        guard row >= 0, let it = outline.item(atRow: row) as? SidebarItem, !it.isGroup else { return }
        if it.book == model.book { refreshGrid(); return }
        model.jump(book: it.book, chapter: 1)
    }
}
