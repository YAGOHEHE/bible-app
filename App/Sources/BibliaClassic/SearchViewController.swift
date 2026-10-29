import AppKit
import BibliaCore
import ClassicKit

private final class SearchTable: NSTableView {
    var onReturn: (() -> Void)?
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 76 { onReturn?(); return }
        super.keyDown(with: event)
    }
}

private final class SearchCell: NSTableCellView {
    let title = NSTextField(labelWithString: "")
    let detail = NSTextField(labelWithString: "")
    let count = NSTextField(labelWithString: "")
    let button = NSButton()
    override init(frame: NSRect) {
        super.init(frame: frame)
        for t in [title, detail, count] { t.translatesAutoresizingMaskIntoConstraints = false; addSubview(t) }
        detail.maximumNumberOfLines = 4
        detail.lineBreakMode = .byTruncatingTail
        detail.cell?.wraps = true
        detail.cell?.isScrollable = false
        title.lineBreakMode = .byTruncatingTail
        count.alignment = .right
        count.setContentHuggingPriority(.required, for: .horizontal)
        count.setContentCompressionResistancePriority(.required, for: .horizontal)
        button.isBordered = false
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setContentHuggingPriority(.required, for: .horizontal)
        addSubview(button)
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            title.topAnchor.constraint(equalTo: topAnchor, constant: 7),
            title.trailingAnchor.constraint(lessThanOrEqualTo: count.leadingAnchor, constant: -6),
            count.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            count.firstBaselineAnchor.constraint(equalTo: title.firstBaselineAnchor),
            button.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            button.centerYAnchor.constraint(equalTo: centerYAnchor),
            detail.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            detail.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            detail.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 2),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }
}

private final class SearchRowView: NSTableRowView {
    var fill = NSColor.selectedContentBackgroundColorCompat
    override func drawSelection(in dirtyRect: NSRect) {
        guard isSelected else { return }
        fill.setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 4, dy: 1), xRadius: 5, yRadius: 5).fill()
    }
    override var isEmphasized: Bool { get { true } set {} }
}

/// S05: panel «Buscar» de la barra lateral.
final class SearchViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    enum Line: Equatable {
        case header(book: Int, count: Int)
        case hit(SearchHit)
        case more(Int)
        case historyHeader
        case historyItem(String)
    }

    let model: ReaderModel
    private let settings: ClassicSettings
    let search: SearchModel
    private let field = NSSearchField()
    private let translationPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let scopePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let summary = NSTextField(labelWithString: "")
    private let info = NSTextField(wrappingLabelWithString: "")
    private let table = SearchTable()
    private let scroll = NSScrollView()
    private let topLine = NSBox()
    private var lines: [Line] = []
    private var palette = ReaderPalette.light
    private var heightCache: [String: CGFloat] = [:]
    private var suggestion: SearchSuggestion?
    private var infoTopToSummary: NSLayoutConstraint?

    init(model: ReaderModel, settings: ClassicSettings) {
        self.model = model; self.settings = settings
        let user = model.userStoreForUI
        let db = model.bible
        search = SearchModel(provider: db.map { RepositorySearchProvider(db: $0) } ?? EmptySearchProvider(), user: user,
                             translationId: model.translationId)
        super.init(nibName: nil, bundle: nil)
        search.currentBook = model.book
        search.allTranslationIds = model.translations.map(\.id)
        search.onChange = { [weak self] in self?.refresh() }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) no se usa") }

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 230, height: 500))
        field.placeholderString = "Buscar en la Biblia  (⌘F)"
        field.delegate = self
        field.target = self
        field.action = #selector(submitted(_:))
        field.sendsWholeSearchString = true
        field.setAccessibilityLabel("Buscar")
        field.toolTip = "Escribe una palabra o frase. Usa «/» para buscar varias: gracia/paz"
        for p in [translationPopup, scopePopup] {
            p.controlSize = .small
            p.font = NSFont.systemFont(ofSize: 12)
            p.target = self
        }
        translationPopup.action = #selector(translationPicked(_:))
        translationPopup.setAccessibilityLabel("Versión en la que buscar")
        scopePopup.action = #selector(scopePicked(_:))
        scopePopup.setAccessibilityLabel("Alcance de la búsqueda")
        for c in SearchScopeChoice.allCases { scopePopup.addItem(withTitle: c.label) }
        summary.font = NSFont.systemFont(ofSize: 11)
        summary.lineBreakMode = .byTruncatingTail
        info.font = NSFont.systemFont(ofSize: 12)
        info.isSelectable = false
        info.maximumNumberOfLines = 0
        info.addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(infoClicked(_:))))

        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("c"))
        table.addTableColumn(col)
        table.headerView = nil
        table.intercellSpacing = NSSize(width: 0, height: 0)
        table.selectionHighlightStyle = .regular
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.action = #selector(rowClicked(_:))
        table.onReturn = { [weak self] in self?.rowClicked(nil) }
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.setAccessibilityLabel("Resultados de la búsqueda")
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        topLine.boxType = .separator

        for v in [field, translationPopup, scopePopup, summary, info, topLine, scroll] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(v)
        }
        let i = NSLayoutConstraint(item: info, attribute: .top, relatedBy: .equal, toItem: summary, attribute: .bottom, multiplier: 1, constant: 6)
        infoTopToSummary = i
        NSLayoutConstraint.activate([
            field.topAnchor.constraint(equalTo: root.topAnchor, constant: 0),
            field.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 10),
            field.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -10),
            translationPopup.topAnchor.constraint(equalTo: field.bottomAnchor, constant: 6),
            translationPopup.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 8),
            scopePopup.leadingAnchor.constraint(equalTo: translationPopup.trailingAnchor, constant: 6),
            scopePopup.centerYAnchor.constraint(equalTo: translationPopup.centerYAnchor),
            scopePopup.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -8),
            translationPopup.widthAnchor.constraint(equalTo: scopePopup.widthAnchor, multiplier: 0.62),
            summary.topAnchor.constraint(equalTo: translationPopup.bottomAnchor, constant: 8),
            summary.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            summary.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
            i,
            info.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            info.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
            topLine.topAnchor.constraint(equalTo: info.bottomAnchor, constant: 6),
            topLine.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            topLine.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: topLine.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])
        view = root

        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(translationChanged), name: .classicTranslationChanged, object: model)
        nc.addObserver(self, selector: #selector(chapterChanged), name: .classicChapterChanged, object: model)
        nc.addObserver(self, selector: #selector(themeChanged), name: .classicSettingsChanged, object: settings)
        rebuildTranslationPopup()
        applyPalette()
        refresh()
    }

    // MARK: tema / popups

    private func applyPalette() {
        palette = ReaderPalette.resolve(settings.theme)
        summary.textColor = palette.textMuted
        info.textColor = palette.textSecondary
        scroll.scrollerKnobStyle = palette.isDark ? .light : .default
        table.backgroundColor = palette.surface
        heightCache = [:]
    }
    @objc private func themeChanged() { applyPalette(); table.reloadData() }

    private func rebuildTranslationPopup() {
        translationPopup.removeAllItems()
        for t in model.translations {
            translationPopup.addItem(withTitle: t.id)
            translationPopup.lastItem?.representedObject = t.id
        }
        translationPopup.selectItem(withTitle: search.translationId)
    }

    @objc private func translationChanged() {
        search.allTranslationIds = model.translations.map(\.id)
        if search.translationId != model.translationId {
            search.translationId = model.translationId
            translationPopup.selectItem(withTitle: model.translationId)
            if !search.isIdle { search.setTranslation(model.translationId) }
        }
    }
    @objc private func chapterChanged() { search.currentBook = model.book }

    @objc private func translationPicked(_ s: NSPopUpButton) {
        guard let id = s.selectedItem?.representedObject as? String else { return }
        search.setTranslation(id)
    }
    @objc private func scopePicked(_ s: NSPopUpButton) {
        search.currentBook = model.book
        search.setScope(SearchScopeChoice(rawValue: s.indexOfSelectedItem) ?? .all)
    }

    // MARK: campo

    func focusField(selectAll: Bool = true) {
        view.window?.makeFirstResponder(field)
        if selectAll { field.selectText(nil); field.currentEditor()?.selectAll(nil) }
    }

    func controlTextDidChange(_ obj: Notification) {
        if let ed = field.currentEditor() as? NSTextView, ed.hasMarkedText() { return }   // composición IME en curso
        search.currentBook = model.book
        search.queryChanged(field.stringValue)
    }
    @objc private func submitted(_ s: NSSearchField) {
        search.currentBook = model.book
        search.submit(s.stringValue)
    }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        if sel == #selector(NSResponder.cancelOperation(_:)), !field.stringValue.isEmpty {
            field.stringValue = ""
            search.queryChanged("")
            return true
        }
        if sel == #selector(NSResponder.moveDown(_:)), !lines.isEmpty {
            view.window?.makeFirstResponder(table)
            if table.selectedRow < 0, let first = lines.firstIndex(where: { if case .hit = $0 { return true } else { return false } }) {
                table.selectRowIndexes(IndexSet(integer: first), byExtendingSelection: false)
            }
            return true
        }
        return false
    }

    /// Lanza una consulta del historial / sugerencia.
    func run(_ q: String) {
        field.stringValue = q
        search.currentBook = model.book
        search.submit(q)
    }

    // MARK: estado -> vista

    private func refresh() {
        heightCache = [:]
        suggestion = nil
        var newLines: [Line] = []
        var infoText = NSAttributedString(string: "")
        var sum = ""
        let small = NSFont.systemFont(ofSize: 12)
        func plain(_ s: String) -> NSAttributedString { NSAttributedString(string: s, attributes: [.font: small, .foregroundColor: palette.textSecondary]) }
        switch search.state {
        case .idle:
            infoText = plain("Escribe una palabra o frase (3 letras o más; en chino basta 1 carácter). Usa «/» para buscar varias a la vez: gracia/paz.")
            let recent = search.recentQueries()
            if !recent.isEmpty { newLines = [.historyHeader] + recent.map { .historyItem($0) } }
        case .loading:
            sum = "Buscando…"
        case .results(let r):
            sum = "\(r.total) \(r.total == 1 ? "resultado" : "resultados") en \(r.translationId) · \(r.bookCount) \(r.bookCount == 1 ? "libro" : "libros")"
            newLines = SearchRow.rows(r).map {
                switch $0 {
                case .header(let b, let c): return .header(book: b, count: c)
                case .hit(let h): return .hit(h)
                case .more(let n): return .more(n)
                }
            }
        case .empty(let q, let t, let sug):
            sum = "0 resultados en \(t)"
            let m = NSMutableAttributedString(attributedString: plain("Sin resultados para «\(q)» en \(t)."))
            if let s = sug {
                suggestion = s
                m.append(plain("\n"))
                m.append(NSAttributedString(string: "«\(q)» aparece \(s.count) \(s.count == 1 ? "vez" : "veces") en \(s.translationId) — ", attributes: [
                    .font: small, .foregroundColor: palette.textSecondary]))
                m.append(NSAttributedString(string: "Buscar en \(s.translationId)", attributes: [
                    .font: NSFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: palette.accent,
                    .underlineStyle: NSUnderlineStyle.single.rawValue]))
            } else {
                m.append(plain("\nPrueba con otra palabra, otro alcance o otra versión."))
            }
            infoText = m
        case .error(let msg):
            sum = "Error"
            infoText = NSAttributedString(string: msg, attributes: [.font: small, .foregroundColor: NSColor.systemRed])
        }
        summary.stringValue = sum
        info.attributedStringValue = infoText
        info.isHidden = infoText.length == 0
        info.setAccessibilityLabel(infoText.string)
        lines = newLines
        table.reloadData()
        if let id = search.activeHitId, let row = lines.firstIndex(where: { if case .hit(let h) = $0 { return h.id == id } else { return false } }) {
            table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
        view.needsLayout = true
    }

    @objc private func infoClicked(_ g: NSClickGestureRecognizer) {
        guard let s = suggestion else { return }
        translationPopup.selectItem(withTitle: s.translationId)
        model.setTranslation(s.translationId)      // el lector sigue a la búsqueda
        search.setTranslation(s.translationId)
    }

    // MARK: abrir resultados

    func open(_ hit: SearchHit) {
        search.markActive(hit)
        search.remember()
        model.navigate(to: BibleRef(book: hit.book, chapter: hit.chapter, verseFrom: hit.verse, verseTo: hit.verse),
                       translation: hit.translationId, terms: search.terms)
        if let row = lines.firstIndex(where: { if case .hit(let h) = $0 { return h.id == hit.id } else { return false } }) {
            table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            table.scrollRowToVisible(row)
        }
    }

    /// ⌘G (+1) / ⇧⌘G (-1). Devuelve false si no hay más resultados.
    @discardableResult
    func advance(_ d: Int) -> Bool {
        guard let h = search.advance(d) else { return false }
        open(h)
        return true
    }

    @objc private func rowClicked(_ sender: Any?) {
        let row = table.clickedRow >= 0 && sender != nil ? table.clickedRow : table.selectedRow
        guard lines.indices.contains(row) else { return }
        switch lines[row] {
        case .hit(let h): open(h)
        case .more: search.loadMore()
        case .historyItem(let q): run(q)
        default: break
        }
    }

    @objc private func clearHistory() {
        search.clearHistory()
        refresh()
    }

    // MARK: tabla

    func numberOfRows(in tableView: NSTableView) -> Int { lines.count }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        switch lines[row] { case .header, .historyHeader: return false; default: return true }
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let r = SearchRowView(); r.fill = palette.selection; return r
    }

    private func hitText(_ h: SearchHit) -> NSAttributedString {
        let terms = search.terms
        return SearchSnippet.attributed(h, terms: terms, font: model.isLatinTranslation(h.translationId) ? NSFont.systemFont(ofSize: 12) : ReaderFonts.cjk(size: 13),
                                        color: palette.textSecondary, matchBackground: palette.searchMatch, matchColor: palette.textPrimary)
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        switch lines[row] {
        case .header, .historyHeader: return 26
        case .more: return 34
        case .historyItem: return 26
        case .hit(let h):
            let w = max(120, table.bounds.width - 32)
            let key = "\(h.id)@\(Int(w))"
            if let c = heightCache[key] { return c }
            let a = hitText(h)
            let r = a.boundingRect(with: NSSize(width: w, height: 1000), options: [.usesLineFragmentOrigin, .usesFontLeading])
            let lineH = ceil(a.size().height)
            let n = min(4, max(1, Int(ceil(r.height / lineH))))
            let hgt = 7 + 16 + 2 + CGFloat(n) * (lineH + 2) + 8
            heightCache[key] = hgt
            return hgt
        }
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("cell")
        let cell = (tableView.makeView(withIdentifier: id, owner: nil) as? SearchCell) ?? {
            let c = SearchCell(frame: .zero); c.identifier = id; return c
        }()
        cell.detail.isHidden = true; cell.count.isHidden = true; cell.button.isHidden = true
        cell.title.alignment = .left
        switch lines[row] {
        case .header(let b, let n):
            cell.title.stringValue = model.bookName(b, translation: search.translationId).uppercased()
            cell.title.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
            cell.title.textColor = palette.textMuted
            cell.count.isHidden = false
            cell.count.stringValue = "\(n)"
            cell.count.font = NSFont.systemFont(ofSize: 11)
            cell.count.textColor = palette.textMuted
        case .hit(let h):
            cell.title.stringValue = RefLabel.text(bookName: model.bookName(h.book, translation: h.translationId), chapter: h.chapter, from: h.verse, to: h.verse)
            cell.title.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
            cell.title.textColor = palette.accent
            cell.detail.isHidden = false
            cell.detail.attributedStringValue = hitText(h)
            cell.detail.preferredMaxLayoutWidth = max(120, table.bounds.width - 26)
            cell.detail.lineBreakMode = .byTruncatingTail
        case .more(let n):
            cell.title.stringValue = "Mostrar más (\(n))"
            cell.title.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
            cell.title.textColor = palette.accent
        case .historyHeader:
            cell.title.stringValue = "BÚSQUEDAS RECIENTES"
            cell.title.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
            cell.title.textColor = palette.textMuted
            cell.button.isHidden = false
            cell.button.attributedTitle = NSAttributedString(string: "Borrar historial", attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .semibold), .foregroundColor: palette.accent])
            cell.button.target = self
            cell.button.action = #selector(clearHistory)
            cell.button.setAccessibilityLabel("Borrar historial de búsquedas")
        case .historyItem(let q):
            cell.title.stringValue = q
            cell.title.font = NSFont.systemFont(ofSize: 13)
            cell.title.textColor = palette.textPrimary
        }
        return cell
    }
}

private final class EmptySearchProvider: SearchProviding {
    func page(query: String, translationId: String, scope: SearchRepository.Scope, limit: Int) throws -> SearchPage {
        SearchPage(hits: [], total: 0, perBook: [:])
    }
    func counts(query: String, scope: SearchRepository.Scope, translationIds: [String]) -> [(id: String, count: Int)] { [] }
}
