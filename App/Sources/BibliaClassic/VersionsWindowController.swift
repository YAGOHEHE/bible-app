import AppKit
import BibliaCore
import ClassicKit

/// S04: gestor de versiones (⌥⌘V). Columnas (máx. 3), versión principal, orden y glosas. Todo se aplica en vivo.
final class VersionsWindowController: NSWindowController {
    private let model: ReaderModel
    private let rowsStack = NSStackView()
    private let status = NSTextField(labelWithString: "")
    private var order: [String] = []

    init(model: ReaderModel) {
        self.model = model
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 560),
                         styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = "Versiones"
        w.isReleasedWhenClosed = false
        super.init(window: w)
        build()
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(refresh), name: .classicParallelChanged, object: model)
        nc.addObserver(self, selector: #selector(refresh), name: .classicTranslationChanged, object: model)
        refresh()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) no se usa") }

    func show() {
        refresh()
        window?.center()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    private static let widths: [CGFloat] = [64, 74, 330, 60, 70, 56]

    private func build() {
        guard let content = window?.contentView else { return }
        let title = NSTextField(labelWithString: "Versiones de la Biblia")
        title.font = NSFont.boldSystemFont(ofSize: 15)
        let help = NSTextField(wrappingLabelWithString: "Columnas: la versión principal más hasta dos activadas (3 como máximo en total). Glosas: hasta 3 versiones bajo cada versículo del modo intercalado, sin contar la principal. El orden de la lista decide el orden de las columnas.")
        help.font = NSFont.systemFont(ofSize: 11)
        help.textColor = .secondaryLabelColor
        help.preferredMaxLayoutWidth = 740

        let header = row(["Columna", "Principal", "Versión", "Strong", "Orden", "Glosa"].map { t in
            let l = NSTextField(labelWithString: t); l.font = NSFont.systemFont(ofSize: 11, weight: .semibold); l.textColor = .secondaryLabelColor; return l })

        rowsStack.orientation = .vertical
        rowsStack.alignment = .leading
        rowsStack.spacing = 6

        status.font = NSFont.systemFont(ofSize: 11)
        status.textColor = .secondaryLabelColor

        let root = NSStackView(views: [title, help, header, rowsStack, status])
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 10
        root.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            root.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            root.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
        ])
    }

    private func row(_ views: [NSView]) -> NSStackView {
        for (i, v) in views.enumerated() where i < Self.widths.count {
            v.translatesAutoresizingMaskIntoConstraints = false
            v.widthAnchor.constraint(equalToConstant: Self.widths[i]).isActive = true
        }
        let s = NSStackView(views: views)
        s.orientation = .horizontal
        s.alignment = .centerY
        s.spacing = 8
        return s
    }

    @objc private func refresh() {
        let vs = model.parallel.versions
        order = vs.order
        for v in rowsStack.arrangedSubviews { rowsStack.removeArrangedSubview(v); v.removeFromSuperview() }
        let primary = model.translationId
        for (i, id) in order.enumerated() {
            guard let t = model.translations.first(where: { $0.id == id }) else { continue }
            let col = NSButton(checkboxWithTitle: "", target: self, action: #selector(columnToggled(_:)))
            col.tag = i
            col.state = (id == primary || vs.enabled.contains(id)) ? .on : .off
            col.isEnabled = VersionManagerLogic.canToggleColumn(vs, id: id, primary: primary)
            col.setAccessibilityLabel("\(t.id) en columnas")

            let pr = NSButton(radioButtonWithTitle: "", target: self, action: #selector(primaryPicked(_:)))
            pr.tag = i
            pr.state = id == primary ? .on : .off
            pr.setAccessibilityLabel("\(t.id) como versión principal")

            let name = NSTextField(labelWithString: "\(t.id) · \(t.name)")
            name.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
            name.lineBreakMode = .byTruncatingTail
            let detail = NSTextField(labelWithString: "\(languageLabel(t.language)) · Licencia: \(t.license ?? "—") · \(t.sourceURL ?? "sin fuente")")
            detail.font = NSFont.systemFont(ofSize: 10.5)
            detail.textColor = .secondaryLabelColor
            detail.lineBreakMode = .byTruncatingTail
            detail.toolTip = "\(t.name)\nLicencia: \(t.license ?? "—")\nFuente: \(t.sourceURL ?? "—")"
            let nameStack = NSStackView(views: [name, detail])
            nameStack.orientation = .vertical; nameStack.alignment = .leading; nameStack.spacing = 1

            let strong = NSTextField(labelWithString: t.hasStrongs ? "Strong" : "")
            strong.font = NSFont.systemFont(ofSize: 11)
            strong.textColor = .secondaryLabelColor

            let up = NSButton(title: "▲", target: self, action: #selector(orderUp(_:)))
            let down = NSButton(title: "▼", target: self, action: #selector(orderDown(_:)))
            for b in [up, down] { b.bezelStyle = .smallSquare; b.tag = i; b.font = NSFont.systemFont(ofSize: 10) }
            up.isEnabled = i > 0; down.isEnabled = i < order.count - 1
            up.setAccessibilityLabel("Subir \(t.id)"); down.setAccessibilityLabel("Bajar \(t.id)")
            let ud = NSStackView(views: [up, down]); ud.spacing = 2

            let gl = NSButton(checkboxWithTitle: "", target: self, action: #selector(glossToggled(_:)))
            gl.tag = i
            gl.state = model.parallel.glosses.contains(id) && id != primary ? .on : .off
            gl.isEnabled = model.parallel.glosses.canAdd(id, primary: primary)
            gl.setAccessibilityLabel("\(t.id) como glosa")

            let r = row([col, pr, nameStack, strong, ud, gl])
            rowsStack.addArrangedSubview(r)
        }
        let cols = model.columnIds.joined(separator: " · ")
        let gl = model.glossIds.isEmpty ? "ninguna" : model.glossIds.joined(separator: " · ")
        status.stringValue = "Columnas: \(cols).   Glosas: \(gl)."
        let h = CGFloat(120 + order.count * 40 + 70)
        if let w = window, abs(w.contentView!.frame.height - h) > 1 { w.setContentSize(NSSize(width: 800, height: h)) }
    }

    private func id(_ sender: NSButton) -> String? { order.indices.contains(sender.tag) ? order[sender.tag] : nil }

    @objc private func columnToggled(_ s: NSButton) {
        guard let i = id(s) else { return }
        var vs = model.parallel.versions
        if VersionManagerLogic.toggleColumn(&vs, id: i, primary: model.translationId) { model.setVersionSet(vs) } else { NSSound.beep() }
        refresh()
    }
    @objc private func primaryPicked(_ s: NSButton) {
        if let i = id(s) { model.setTranslation(i) }
        refresh()
    }
    @objc private func orderUp(_ s: NSButton) { move(s, -1) }
    @objc private func orderDown(_ s: NSButton) { move(s, 1) }
    private func move(_ s: NSButton, _ d: Int) {
        guard let i = id(s) else { return }
        var vs = model.parallel.versions
        if VersionManagerLogic.move(&vs, id: i, by: d) { model.setVersionSet(vs) }
        refresh()
    }
    @objc private func glossToggled(_ s: NSButton) {
        guard let i = id(s) else { return }
        if !model.toggleGloss(i) { NSSound.beep() }
        refresh()
    }
}
