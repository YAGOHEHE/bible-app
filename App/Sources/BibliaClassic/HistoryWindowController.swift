import AppKit
import BibliaCore
import ClassicKit

private final class HistoryCell: NSTableCellView {
    let title = NSTextField(labelWithString: "")
    let detail = NSTextField(labelWithString: "")
    let time = NSTextField(labelWithString: "")
    override init(frame: NSRect) {
        super.init(frame: frame)
        for t in [title, detail, time] { t.translatesAutoresizingMaskIntoConstraints = false; addSubview(t) }
        time.alignment = .right
        time.setContentHuggingPriority(.required, for: .horizontal)
        time.setContentCompressionResistancePriority(.required, for: .horizontal)
        title.lineBreakMode = .byTruncatingTail
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            title.topAnchor.constraint(equalTo: topAnchor, constant: 7),
            title.trailingAnchor.constraint(lessThanOrEqualTo: time.leadingAnchor, constant: -8),
            time.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            time.firstBaselineAnchor.constraint(equalTo: title.firstBaselineAnchor),
            detail.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            detail.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 1),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }
}

/// S07: historial de lectura (⌘Y). Hoy / Ayer / fecha; clic navega sin añadir otra fila.
final class HistoryWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    private enum Line { case section(String), row(HistoryRow) }
    private let model: ReaderModel
    private let settings: ClassicSettings
    private let table = NSTableView()
    private let scroll = NSScrollView()
    private let emptyLabel = NSTextField(wrappingLabelWithString: "Todavía no hay historial de lectura.\nLos capítulos que leas y los saltos que hagas aparecerán aquí.")
    private let clearButton = NSButton(title: "Borrar historial", target: nil, action: nil)
    private var lines: [Line] = []
    var onNavigate: ((BibleRef, String) -> Void)?

    init(model: ReaderModel, settings: ClassicSettings) {
        self.model = model; self.settings = settings
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 540),
                         styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        w.title = "Historial de lectura"
        w.minSize = NSSize(width: 320, height: 300)
        w.setFrameAutosaveName("HistoryWindow")
        super.init(window: w)
        build(in: w)
        NotificationCenter.default.addObserver(self, selector: #selector(changed), name: .classicChapterChanged, object: model)
        NotificationCenter.default.addObserver(self, selector: #selector(themeChanged), name: .classicSettingsChanged, object: settings)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) no se usa") }

    private func build(in w: NSWindow) {
        let root = NSView(frame: w.contentView!.bounds)
        root.autoresizingMask = [.width, .height]
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("c"))
        table.addTableColumn(col)
        table.headerView = nil
        table.intercellSpacing = .zero
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.action = #selector(rowClicked(_:))
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.setAccessibilityLabel("Historial de lectura")
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        clearButton.bezelStyle = .rounded
        clearButton.target = self
        clearButton.action = #selector(confirmClear(_:))
        emptyLabel.alignment = .center
        emptyLabel.font = NSFont.systemFont(ofSize: 13)
        emptyLabel.isHidden = true
        let line = NSBox(); line.boxType = .separator
        for v in [scroll, line, clearButton, emptyLabel] as [NSView] { v.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(v) }
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: root.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: line.topAnchor),
            line.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            line.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            line.bottomAnchor.constraint(equalTo: clearButton.topAnchor, constant: -10),
            clearButton.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -14),
            clearButton.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -10),
            emptyLabel.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: root.centerYAnchor, constant: -20),
            emptyLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 300),
        ])
        w.contentView = root
        applyTheme()
    }

    private func applyTheme() {
        guard let w = window else { return }
        MainWindowController.apply(theme: settings.theme, to: w)
        let pal = ReaderPalette.resolve(settings.theme)
        table.backgroundColor = pal.background
        emptyLabel.textColor = pal.textMuted
        scroll.scrollerKnobStyle = pal.isDark ? .light : .default
    }
    @objc private func themeChanged() { applyTheme(); table.reloadData() }
    @objc private func changed() { if window?.isVisible == true { reload() } }

    func show() {
        reload()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    func reload() {
        let m = model
        let sections = HistoryModel.sections(model.historyEntries(), bookName: { id, b in m.bookName(b, translation: id) })
        lines = sections.flatMap { s -> [Line] in [.section(s.title)] + s.rows.map { .row($0) } }
        table.reloadData()
        emptyLabel.isHidden = !lines.isEmpty
        clearButton.isEnabled = !lines.isEmpty
        scroll.isHidden = lines.isEmpty
    }

    @objc private func rowClicked(_ s: Any?) {
        let r = table.clickedRow
        guard lines.indices.contains(r), case .row(let h) = lines[r] else { return }
        onNavigate?(h.ref, h.translationId)
    }

    @objc private func confirmClear(_ s: Any?) {
        guard let w = window else { return }
        let a = NSAlert()
        a.messageText = "¿Borrar todo el historial de lectura?"
        a.informativeText = "Se eliminarán todas las entradas. Esta acción no se puede deshacer."
        a.addButton(withTitle: "Borrar historial")
        a.addButton(withTitle: "Cancelar").keyEquivalent = "\u{1b}"     // Esc cancela
        a.alertStyle = .warning
        a.beginSheetModal(for: w) { [weak self] resp in
            guard resp == .alertFirstButtonReturn else { return }
            self?.model.clearHistory()
            self?.reload()
        }
    }

    // MARK: tabla

    func numberOfRows(in tableView: NSTableView) -> Int { lines.count }
    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { if case .row = lines[row] { return true } else { return false } }
    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat { if case .section = lines[row] { return 30 } else { return 44 } }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let pal = ReaderPalette.resolve(settings.theme)
        let id = NSUserInterfaceItemIdentifier("h")
        let cell = (tableView.makeView(withIdentifier: id, owner: nil) as? HistoryCell) ?? {
            let c = HistoryCell(frame: .zero); c.identifier = id; return c
        }()
        switch lines[row] {
        case .section(let t):
            cell.title.stringValue = t.uppercased()
            cell.title.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
            cell.title.textColor = pal.textMuted
            cell.detail.stringValue = ""; cell.time.stringValue = ""
        case .row(let h):
            cell.title.stringValue = h.label
            cell.title.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
            cell.title.textColor = pal.textPrimary
            cell.detail.stringValue = "\(h.translationId) · \(h.kind)"
            cell.detail.font = NSFont.systemFont(ofSize: 11)
            cell.detail.textColor = pal.textMuted
            cell.time.stringValue = h.time
            cell.time.font = NSFont.systemFont(ofSize: 11)
            cell.time.textColor = pal.textMuted
        }
        return cell
    }
}
