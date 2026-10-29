import AppKit
import BibliaCore
import ClassicKit

/// Chip de tipo («Todo 6», «Notas 3», …).
private final class ChipButton: NSButton {
    var palette = ReaderPalette.light
    var chipTitle = ""
    var chosen = false { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { false }
    override func draw(_ dirtyRect: NSRect) {
        let r = bounds.insetBy(dx: 0, dy: 1)
        let path = NSBezierPath(roundedRect: r, xRadius: r.height / 2, yRadius: r.height / 2)
        (chosen ? palette.accent : palette.border.withAlphaComponent(isHighlighted ? 1 : 0.55)).setFill()
        path.fill()
        let a = NSAttributedString(string: chipTitle, attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: chosen ? .semibold : .regular),
            .foregroundColor: chosen ? palette.pillText : palette.textPrimary])
        let s = a.size()
        a.draw(at: NSPoint(x: (bounds.width - s.width) / 2, y: (bounds.height - s.height) / 2))
    }
}

/// Fila del panel: icono por tipo, referencia, fecha, título de la nota y fragmento del versículo.
private final class AnnotationCell: NSView {
    var item: AnnotationItem?
    var refText = "", dateText = "", titleText = "", snippet = ""
    var palette = ReaderPalette.light
    override var isFlipped: Bool { true }

    static func height(item: AnnotationItem, title: String, snippet: String, width: CGFloat) -> CGFloat {
        var h: CGFloat = 8 + 17
        if !title.isEmpty { h += 17 }
        let sn = NSAttributedString(string: snippet.isEmpty ? "—" : snippet, attributes: [.font: NSFont.systemFont(ofSize: 11.5)])
        let bound = sn.boundingRect(with: NSSize(width: max(60, width - 36), height: 1000), options: [.usesLineFragmentOrigin])
        h += min(ceil(bound.height), 32) + 4
        return h + 6
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let it = item else { return }
        let ix: CGFloat = 12, iy: CGFloat = 11
        switch it.kind {
        case .note:
            NSAttributedString(string: AnnotationOverlays.noteGlyph, attributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: palette.accent])
                .draw(at: NSPoint(x: ix - 1, y: iy - 3))
        case .bookmark:
            NSAttributedString(string: AnnotationOverlays.bookmarkGlyph, attributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: palette.bookmarkMarker])
                .draw(at: NSPoint(x: ix, y: iy - 3))
        case .highlight:
            let r = NSRect(x: ix, y: iy, width: 12, height: 12)
            let c = NSBezierPath(ovalIn: r)
            (it.color.map { palette.highlight($0) } ?? palette.surface).setFill(); c.fill()
            palette.textMuted.setStroke(); c.lineWidth = 1; c.stroke()
        }
        let left: CGFloat = 32
        let dateA = NSAttributedString(string: dateText, attributes: [.font: NSFont.systemFont(ofSize: 10.5), .foregroundColor: palette.textMuted])
        let dw = dateA.size().width
        dateA.draw(at: NSPoint(x: bounds.width - dw - 10, y: 10))
        let ps = NSMutableParagraphStyle(); ps.lineBreakMode = .byTruncatingTail
        NSAttributedString(string: refText, attributes: [.font: NSFont.systemFont(ofSize: 13, weight: .semibold), .foregroundColor: palette.textPrimary, .paragraphStyle: ps])
            .draw(in: NSRect(x: left, y: 8, width: max(0, bounds.width - left - dw - 18), height: 17))
        var y: CGFloat = 8 + 17
        if !titleText.isEmpty {
            NSAttributedString(string: titleText, attributes: [.font: NSFont.systemFont(ofSize: 12.5), .foregroundColor: palette.textPrimary, .paragraphStyle: ps])
                .draw(in: NSRect(x: left, y: y, width: max(0, bounds.width - left - 10), height: 17))
            y += 17
        }
        let sp = NSMutableParagraphStyle(); sp.lineBreakMode = .byTruncatingTail
        let h = bounds.height - y - 6
        NSAttributedString(string: snippet.isEmpty ? "—" : snippet, attributes: [.font: NSFont.systemFont(ofSize: 11.5), .foregroundColor: palette.textSecondary, .paragraphStyle: sp])
            .draw(with: NSRect(x: left, y: y + 2, width: max(0, bounds.width - left - 10), height: h), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
    }
}

private final class NotesRowView: NSTableRowView {
    var fill = NSColor.selectedContentBackgroundColorCompat
    override func drawSelection(in dirtyRect: NSRect) {
        guard isSelected else { return }
        fill.setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 4, dy: 1), xRadius: 5, yRadius: 5).fill()
    }
    override var isEmphasized: Bool { get { true } set {} }
}

private final class FlippedRoot: NSView { override var isFlipped: Bool { true } }

/// Panel «Notas» de la barra lateral: notas, resaltados y marcadores con filtros, búsqueda y orden.
final class NotesPanelViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate, NSSearchFieldDelegate {
    let list: AnnotationListModel
    private let reader: ReaderModel
    private let annotations: AnnotationsModel
    private let settings: ClassicSettings
    private var palette = ReaderPalette.light
    private var chips: [AnnotationKindFilter: ChipButton] = [:]
    private var swatches: [SwatchButton] = []
    private let colorLabel = NSTextField(labelWithString: "Color")
    private let bookPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let sortPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let field = NSSearchField()
    private let table = NSTableView()
    private let scroll = NSScrollView()
    private let topLine = NSBox()
    private let emptyTitle = NSTextField(labelWithString: "")
    private let emptyBody = NSTextField(wrappingLabelWithString: "")
    private let clearButton = NSButton(title: "Quitar filtros", target: nil, action: nil)
    private var snippets: [String: String] = [:]
    private var rowHeights: [CGFloat] = []
    var onOpen: ((AnnotationItem) -> Void)?

    init(model: ReaderModel, annotations: AnnotationsModel, settings: ClassicSettings) {
        reader = model; self.annotations = annotations; self.settings = settings
        list = AnnotationListModel(store: annotations.store)
        super.init(nibName: nil, bundle: nil)
        list.onMutation = { [weak annotations] in annotations?.didMutate() }
        list.onRefresh = { [weak self] in self?.listRefreshed() }
    }
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let root = FlippedRoot(frame: NSRect(x: 0, y: 0, width: 260, height: 600))
        for k in AnnotationKindFilter.allCases {
            let c = ChipButton()
            c.isBordered = false; c.title = ""
            c.target = self; c.action = #selector(chipTapped(_:))
            c.tag = AnnotationKindFilter.allCases.firstIndex(of: k) ?? 0
            chips[k] = c
            root.addSubview(c)
        }
        let all = SwatchButton(); all.isAll = true; all.isBordered = false; all.title = ""
        all.setAccessibilityLabel("Todos los colores"); all.toolTip = "Todos los colores"
        all.tag = -1; all.target = self; all.action = #selector(swatchTapped(_:))
        swatches.append(all)
        for (i, c) in HighlightColor.allCases.enumerated() {
            let s = SwatchButton(); s.color = c; s.isBordered = false; s.title = ""
            s.setAccessibilityLabel("Color " + c.displayName.lowercased()); s.toolTip = c.displayName
            s.tag = i; s.target = self; s.action = #selector(swatchTapped(_:))
            swatches.append(s)
        }
        swatches.forEach { root.addSubview($0) }
        colorLabel.font = NSFont.systemFont(ofSize: 11)
        root.addSubview(colorLabel)

        bookPopup.target = self; bookPopup.action = #selector(bookPicked)
        bookPopup.setAccessibilityLabel("Filtrar por libro"); bookPopup.toolTip = "Filtrar por libro"
        bookPopup.controlSize = .small; bookPopup.font = NSFont.systemFont(ofSize: 11)
        for t in ["Orden bíblico", "Recientes"] { sortPopup.addItem(withTitle: t) }
        sortPopup.target = self; sortPopup.action = #selector(sortPicked)
        sortPopup.setAccessibilityLabel("Orden de la lista"); sortPopup.toolTip = "Ordenar"
        sortPopup.controlSize = .small; sortPopup.font = NSFont.systemFont(ofSize: 11)
        root.addSubview(bookPopup); root.addSubview(sortPopup)

        field.placeholderString = "Buscar en las notas"
        field.delegate = self
        field.setAccessibilityLabel("Buscar en el texto de las notas")
        root.addSubview(field)
        topLine.boxType = .separator
        root.addSubview(topLine)

        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("ann"))
        table.addTableColumn(col)
        table.headerView = nil
        table.dataSource = self; table.delegate = self
        table.selectionHighlightStyle = .regular
        table.intercellSpacing = NSSize(width: 0, height: 0)
        if #available(macOS 11.0, *) { table.style = .fullWidth }   // sin los 16 pt de margen de macOS 11+
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.target = self; table.action = #selector(rowClicked)
        table.setAccessibilityLabel("Anotaciones")
        let menu = NSMenu(); menu.delegate = self
        table.menu = menu
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        root.addSubview(scroll)

        emptyTitle.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        emptyTitle.alignment = .center
        emptyBody.font = NSFont.systemFont(ofSize: 12)
        emptyBody.alignment = .center
        clearButton.bezelStyle = .rounded
        clearButton.target = self; clearButton.action = #selector(clearTapped)
        for v in [emptyTitle, emptyBody, clearButton] as [NSView] { root.addSubview(v) }
        view = root

        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(annotationsChanged), name: .classicAnnotationsChanged, object: annotations)
        nc.addObserver(self, selector: #selector(translationChanged), name: .classicTranslationChanged, object: reader)
        nc.addObserver(self, selector: #selector(themeChanged), name: .classicSettingsChanged, object: settings)
        rebuildBookPopup()
        applyPalette()
        listRefreshed()
    }

    // MARK: modelo → vista

    private func rebuildBookPopup() {
        bookPopup.removeAllItems()
        bookPopup.addItem(withTitle: "Todos los libros")
        bookPopup.menu?.addItem(.separator())
        for b in 1...66 {
            bookPopup.addItem(withTitle: reader.bookName(b))
            bookPopup.lastItem?.tag = b
        }
        if let b = list.book, let i = bookPopup.itemArray.firstIndex(where: { $0.tag == b }) { bookPopup.selectItem(at: i) } else { bookPopup.selectItem(at: 0) }
    }

    func refresh() { list.refresh() }

    @objc private func annotationsChanged() { if isViewLoaded { list.refresh() } }
    @objc private func translationChanged() {
        guard isViewLoaded else { return }
        snippets = [:]; rebuildBookPopup(); table.reloadData(); recomputeHeights(); table.reloadData()
    }
    @objc private func themeChanged() { applyPalette() }

    private func applyPalette() {
        palette = ReaderPalette.resolve(settings.theme)
        view.wantsLayer = true
        view.layer?.backgroundColor = palette.surface.cgColor
        table.backgroundColor = palette.surface
        scroll.scrollerKnobStyle = palette.isDark ? .light : .default
        colorLabel.textColor = palette.textSecondary
        emptyTitle.textColor = palette.textPrimary
        emptyBody.textColor = palette.textSecondary
        for c in chips.values { c.palette = palette }
        for s in swatches { s.palette = palette }
        table.reloadData()
        syncChips()
    }

    private func listRefreshed() {
        guard isViewLoaded else { return }
        syncChips()
        recomputeHeights()
        table.reloadData()
        let empty = list.items.isEmpty
        scroll.isHidden = empty
        for v in [emptyTitle, emptyBody] as [NSView] { v.isHidden = !empty }
        clearButton.isHidden = !(empty && list.isFiltered)
        if empty { setEmptyText() }
        view.needsLayout = true
        layoutAll()
    }

    private func syncChips() {
        for (k, c) in chips {
            c.chipTitle = "\(k.label) \(k.count(list.counts))"
            c.chosen = list.kind == k
            c.setAccessibilityLabel("\(k.label), \(k.count(list.counts))")
            c.needsDisplay = true
        }
        for s in swatches {
            let isAllSel = s.isAll && list.color == nil
            s.active = isAllSel || (!s.isAll && list.color == s.color)
        }
        let showColor = list.kind == .highlights
        colorLabel.isHidden = !showColor
        swatches.forEach { $0.isHidden = !showColor }
        sortPopup.selectItem(at: list.sort == .canonical ? 0 : 1)
        if field.stringValue != list.text { field.stringValue = list.text }
    }

    private func setEmptyText() {
        let (title, desc): (String, String)
        let q = list.text.trimmingCharacters(in: .whitespaces)
        if !q.isEmpty {
            (title, desc) = ("Sin resultados", "Ninguna nota contiene «\(q)».")
        } else if list.book != nil || list.color != nil {
            (title, desc) = ("Nada con estos filtros", "Prueba con otro libro o color.")
        } else {
            switch list.kind {
            case .all: (title, desc) = ("Aún no hay anotaciones", "Selecciona un versículo para resaltarlo, anotarlo o marcarlo.")
            case .notes: (title, desc) = ("Sin notas", "Selecciona un versículo y pulsa Anotar (⌥⌘N).")
            case .highlights: (title, desc) = ("Sin resaltados", "Selecciona un versículo y elige un color.")
            case .bookmarks: (title, desc) = ("Sin marcadores", "Selecciona un versículo y pulsa Marcador (⌘D).")
            }
        }
        emptyTitle.stringValue = title; emptyBody.stringValue = desc
    }

    // MARK: acciones de los controles

    @objc private func chipTapped(_ b: NSButton) { list.kind = AnnotationKindFilter.allCases[b.tag] }
    @objc private func swatchTapped(_ b: NSButton) { list.color = b.tag < 0 ? nil : HighlightColor.allCases[b.tag] }
    @objc private func bookPicked() { list.book = bookPopup.selectedItem.flatMap { $0.tag > 0 ? $0.tag : nil } }
    @objc private func sortPicked() { list.sort = sortPopup.indexOfSelectedItem == 0 ? .canonical : .updated }
    @objc private func clearTapped() { list.clearFilters(); rebuildBookPopup() }
    func controlTextDidChange(_ obj: Notification) { list.text = field.stringValue }

    @objc private func rowClicked() {
        let r = table.clickedRow
        guard r >= 0, let it = list.items[safe: r] else { return }
        onOpen?(it)
    }

    // MARK: distribución

    override func viewDidLayout() { super.viewDidLayout(); layoutAll() }

    private func layoutAll() {
        guard isViewLoaded else { return }
        let w = view.bounds.width, pad: CGFloat = 10
        let inner = max(60, w - pad * 2)
        var y: CGFloat = 4
        let kinds = AnnotationKindFilter.allCases
        let cw = (inner - 6) / 2
        for (i, k) in kinds.enumerated() {
            chips[k]?.frame = NSRect(x: pad + CGFloat(i % 2) * (cw + 6), y: y + CGFloat(i / 2) * 28, width: cw, height: 24)
        }
        y += 56 + 2
        if list.kind == .highlights {
            colorLabel.frame = NSRect(x: pad, y: y + 5, width: 36, height: 14)
            var x = pad + 38
            for s in swatches { s.frame = NSRect(x: x, y: y - 1, width: 26, height: 26); x += 27 }
            y += 28
        }
        let bw = inner * 0.58
        bookPopup.frame = NSRect(x: pad, y: y, width: bw, height: 22)
        sortPopup.frame = NSRect(x: pad + bw + 4, y: y, width: inner - bw - 4, height: 22)
        y += 28
        field.frame = NSRect(x: pad, y: y, width: inner, height: 22)
        y += 28
        topLine.frame = NSRect(x: 0, y: y, width: w, height: 1)
        y += 1
        scroll.frame = NSRect(x: 0, y: y, width: w, height: max(0, view.bounds.height - y))
        let eh = emptyBody.sizeThatFits(NSSize(width: inner, height: 200)).height
        emptyTitle.frame = NSRect(x: pad, y: y + 40, width: inner, height: 20)
        emptyBody.frame = NSRect(x: pad, y: y + 64, width: inner, height: eh)
        clearButton.sizeToFit()
        clearButton.frame.origin = NSPoint(x: (w - clearButton.frame.width) / 2, y: y + 64 + eh + 10)
        table.tableColumns.first?.width = scroll.contentSize.width
    }

    // MARK: tabla

    private func snippet(_ it: AnnotationItem) -> String {
        let key = "\(it.id)|\(reader.translationId)"
        if let s = snippets[key] { return s }
        let hi = max(it.verseStart, it.verseEnd)
        let s = reader.text(of: BibleRef(book: it.book, chapter: it.chapter, verseFrom: it.verseStart, verseTo: hi)) ?? ""
        snippets[key] = s
        return s
    }

    private func titleOf(_ it: AnnotationItem) -> String { it.kind == .note ? AnnotationListModel.title(of: it.body ?? "") : "" }

    private func recomputeHeights() {
        let w = max(120, scroll.contentSize.width)
        rowHeights = list.items.map { AnnotationCell.height(item: $0, title: titleOf($0), snippet: snippet($0), width: w) }
    }

    func numberOfRows(in tableView: NSTableView) -> Int { list.items.count }
    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat { rowHeights[safe: row] ?? 60 }
    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let r = NotesRowView(); r.fill = palette.selection; return r
    }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let it = list.items[safe: row] else { return nil }
        let cell = AnnotationCell()
        cell.item = it; cell.palette = palette
        cell.refText = RefLabel.text(bookName: reader.bookName(it.book), chapter: it.chapter, from: it.verseStart, to: it.verseEnd)
        cell.dateText = DateText.date(it.updatedAt)
        cell.titleText = titleOf(it)
        cell.snippet = snippet(it)
        let kind: String
        switch it.kind {
        case .note: kind = "Nota"
        case .bookmark: kind = "Marcador"
        case .highlight: kind = "Resaltado " + (it.color?.displayName.lowercased() ?? "")
        }
        cell.setAccessibilityLabel("\(kind), \(cell.refText)" + (cell.titleText.isEmpty ? "" : ". " + cell.titleText))
        return cell
    }

    // MARK: menú contextual

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let r = table.clickedRow
        guard r >= 0, let it = list.items[safe: r] else { return }
        menu.addItem(BlockMenuItem("Ir al pasaje") { [weak self] in self?.onOpen?(it) })
        if it.kind == .highlight {
            let sub = NSMenu(title: "Cambiar color")
            sub.autoenablesItems = false
            for c in HighlightColor.allCases {
                sub.addItem(BlockMenuItem(c.displayName, enabled: it.color != c, checked: it.color == c) { [weak self] in self?.list.recolor(it, to: c) })
            }
            let host = NSMenuItem(title: "Cambiar color", action: nil, keyEquivalent: "")
            host.submenu = sub
            menu.addItem(host)
        }
        menu.addItem(.separator())
        menu.addItem(BlockMenuItem("Eliminar") { [weak self] in self?.requestDelete(it) })
    }

    func requestDelete(_ it: AnnotationItem) {
        guard it.kind == .note, let w = view.window else { list.delete(it); return }
        let a = NSAlert()
        a.messageText = "¿Eliminar esta nota?"
        a.informativeText = RefLabel.text(bookName: reader.bookName(it.book), chapter: it.chapter, from: it.verseStart, to: it.verseEnd)
            + "\nEsta acción no se puede deshacer."
        a.alertStyle = .warning
        a.addButton(withTitle: "Eliminar"); a.addButton(withTitle: "Cancelar").keyEquivalent = "\u{1b}"     // Esc cancela
        a.beginSheetModal(for: w) { [weak self] resp in if resp == .alertFirstButtonReturn { self?.list.delete(it) } }
    }

    func focusSearch() { view.window?.makeFirstResponder(field) }
}
