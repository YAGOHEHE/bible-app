import AppKit
import BibliaCore
import ClassicKit

/// Botón de fila de la lista de notas del rango (título + versículos).
private final class NoteRowButton: NSButton {
    var selectedRow = false { didSet { needsDisplay = true } }
    var palette = ReaderPalette.light
    var noteTitle = "", rangeLabel = ""
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { false }
    override func draw(_ dirtyRect: NSRect) {
        if selectedRow { palette.selection.setFill(); NSBezierPath(roundedRect: bounds, xRadius: 5, yRadius: 5).fill() }
        let ic = NSAttributedString(string: AnnotationOverlays.noteGlyph, attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: palette.accent])
        ic.draw(at: NSPoint(x: 6, y: (bounds.height - ic.size().height) / 2))
        let r = NSAttributedString(string: rangeLabel, attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: palette.textMuted])
        let rw = r.size().width
        r.draw(at: NSPoint(x: bounds.width - rw - 6, y: (bounds.height - r.size().height) / 2))
        let ps = NSMutableParagraphStyle(); ps.lineBreakMode = .byTruncatingTail
        let t = NSAttributedString(string: noteTitle.isEmpty ? "(sin título)" : noteTitle,
                                   attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: palette.textPrimary, .paragraphStyle: ps])
        t.draw(in: NSRect(x: 24, y: (bounds.height - 15) / 2, width: max(0, bounds.width - 24 - rw - 14), height: 15))
    }
}

/// Pestaña «Nota» del inspector: referencia y texto, notas del rango, editor Markdown con vista previa,
/// fechas y estado de guardado. El modelo (`NoteEditorModel`) hace el autoguardado (600 ms, sin concurrencia).
final class NoteTabView: NSView, NSTextViewDelegate {
    let editorModel: NoteEditorModel
    private let reader: ReaderModel
    private let annotations: AnnotationsModel
    private var palette = ReaderPalette.light

    private let emptyTitle = NSTextField(labelWithString: "Notas")
    private let emptyBody = NSTextField(wrappingLabelWithString: "Selecciona un versículo y pulsa Anotar (⌥⌘N).")
    private let emptyButton = NSButton(title: "Anotar la selección", target: nil, action: nil)

    private let refLabel = NSTextField(labelWithString: "")
    private let passage = NSTextField(wrappingLabelWithString: "")
    private let listTitle = NSTextField(labelWithString: "")
    private var rowButtons: [NoteRowButton] = []
    private let modeControl = NSSegmentedControl(labels: ["Editar", "Vista previa"], trackingMode: .selectOne, target: nil, action: nil)
    private let editorScroll = NSScrollView()
    let editor = NSTextView()
    private let previewScroll = NSScrollView()
    private let previewText = NSTextView()
    private let errorLabel = NSTextField(wrappingLabelWithString: "")
    private let created = NSTextField(labelWithString: "")
    private let modified = NSTextField(labelWithString: "")
    private let status = NSTextField(labelWithString: "")
    private let newButton = NSButton(title: "Nueva nota", target: nil, action: nil)
    private let deleteButton = NSButton(title: "Eliminar", target: nil, action: nil)
    private var syncing = false
    var onRequestNote: (() -> Void)?
    override var isFlipped: Bool { true }

    init(editor model: NoteEditorModel, reader: ReaderModel, annotations: AnnotationsModel) {
        editorModel = model; self.reader = reader; self.annotations = annotations
        super.init(frame: NSRect(x: 0, y: 0, width: 300, height: 600))
        build()
        model.onState = { [weak self] in self?.sync() }
    }
    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        for l in [emptyTitle, emptyBody, refLabel, passage, listTitle, errorLabel, created, modified, status] { addSubview(l) }
        emptyTitle.font = NSFont.systemFont(ofSize: 15, weight: .semibold)
        emptyBody.font = NSFont.systemFont(ofSize: 12)
        emptyBody.alignment = .center
        emptyTitle.alignment = .center
        emptyButton.bezelStyle = .rounded
        emptyButton.target = self; emptyButton.action = #selector(requestTapped)
        addSubview(emptyButton)
        refLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        refLabel.setAccessibilityLabel("Referencia de la nota")
        passage.font = ReaderFonts.latin(size: 13)
        passage.maximumNumberOfLines = 4
        passage.lineBreakMode = .byTruncatingTail
        listTitle.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        errorLabel.font = NSFont.systemFont(ofSize: 11)
        for l in [created, modified, status] { l.font = NSFont.systemFont(ofSize: 11) }
        modeControl.segmentStyle = .rounded
        modeControl.selectedSegment = 0
        modeControl.target = self; modeControl.action = #selector(modePicked)
        modeControl.setAccessibilityLabel("Editar o ver vista previa")
        addSubview(modeControl)

        editor.isRichText = false
        editor.allowsUndo = true
        editor.isEditable = true
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticSpellingCorrectionEnabled = false
        editor.font = NSFont.systemFont(ofSize: 13)
        editor.textContainerInset = NSSize(width: 4, height: 6)
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]
        editor.textContainer?.widthTracksTextView = true
        editor.delegate = self
        editor.setAccessibilityLabel("Texto de la nota, Markdown")
        editor.toolTip = "Markdown: **negrita**, *cursiva*, `código`, [enlace](https://…)"
        editorScroll.documentView = editor
        editorScroll.hasVerticalScroller = true
        editorScroll.autohidesScrollers = true
        editorScroll.borderType = .lineBorder
        addSubview(editorScroll)

        previewText.isEditable = false
        previewText.isSelectable = true
        previewText.textContainerInset = NSSize(width: 6, height: 6)
        previewText.isVerticallyResizable = true
        previewText.isHorizontallyResizable = false
        previewText.autoresizingMask = [.width]
        previewText.textContainer?.widthTracksTextView = true
        previewText.delegate = self
        previewText.setAccessibilityLabel("Vista previa de la nota")
        previewScroll.documentView = previewText
        previewScroll.hasVerticalScroller = true
        previewScroll.autohidesScrollers = true
        previewScroll.borderType = .lineBorder
        addSubview(previewScroll)

        newButton.bezelStyle = .rounded
        newButton.target = self; newButton.action = #selector(newTapped)
        newButton.toolTip = "Añadir otra nota a este versículo"
        deleteButton.bezelStyle = .rounded
        deleteButton.target = self; deleteButton.action = #selector(deleteTapped)
        addSubview(newButton); addSubview(deleteButton)
    }

    func applyPalette(_ p: ReaderPalette) {
        palette = p
        wantsLayer = true
        layer?.backgroundColor = p.background.cgColor
        for l in [emptyTitle, refLabel] { l.textColor = p.textPrimary }
        refLabel.textColor = p.heading
        for l in [emptyBody, passage, listTitle] { l.textColor = p.textSecondary }
        for l in [created, modified, status] { l.textColor = p.textMuted }
        errorLabel.textColor = p.accent
        editor.backgroundColor = p.background; editor.textColor = p.textPrimary; editor.insertionPointColor = p.textPrimary
        editor.selectedTextAttributes = [.backgroundColor: p.selection, .foregroundColor: p.textPrimary]
        editorScroll.backgroundColor = p.background
        previewText.backgroundColor = p.background
        previewScroll.backgroundColor = p.background
        editorScroll.scrollerKnobStyle = p.isDark ? .light : .default
        previewScroll.scrollerKnobStyle = p.isDark ? .light : .default
        previewText.linkTextAttributes = [.foregroundColor: p.accent, .cursor: NSCursor.pointingHand]
        sync()
    }

    // MARK: acciones

    @objc private func requestTapped() { onRequestNote?() }
    @objc private func modePicked() {
        editorModel.preview = modeControl.selectedSegment == 1
        if !editorModel.preview { window?.makeFirstResponder(editor) }
    }
    @objc private func newTapped() { editorModel.newNote(); focusEditor() }
    @objc private func rowTapped(_ b: NSButton) {
        guard let n = editorModel.notes[safe: b.tag] else { return }
        editorModel.select(n.id); focusEditor()
    }
    @objc private func deleteTapped() {
        guard editorModel.selectedId != nil, let w = window else { return }
        let a = NSAlert()
        a.messageText = "¿Eliminar esta nota?"
        a.informativeText = "Esta acción no se puede deshacer."
        a.alertStyle = .warning
        a.addButton(withTitle: "Eliminar")
        a.addButton(withTitle: "Cancelar").keyEquivalent = "\u{1b}"     // Esc cancela
        a.beginSheetModal(for: w) { [weak self] r in
            if r == .alertFirstButtonReturn { self?.editorModel.deleteSelected() }
        }
    }

    func focusEditor() {
        guard !editorModel.preview, !editor.isHidden else { return }
        window?.makeFirstResponder(editor)
    }

    func textDidChange(_ notification: Notification) {
        guard !syncing, (notification.object as? NSTextView) === editor else { return }
        editorModel.edit(editor.string)
    }

    func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
        guard let u = (link as? URL) ?? URL(string: "\(link)"), ["http", "https", "mailto"].contains(u.scheme ?? "") else { return false }
        NSWorkspace.shared.open(u)
        return true
    }

    // MARK: modelo → vista

    func sync() {
        let m = editorModel
        let hasTarget = m.hasTarget
        for v in [emptyTitle, emptyBody, emptyButton] as [NSView] { v.isHidden = hasTarget }
        let editing = [refLabel, passage, listTitle, modeControl, editorScroll, previewScroll, errorLabel, created, modified, status, newButton, deleteButton] as [NSView]
        for v in editing { v.isHidden = !hasTarget }
        emptyButton.isEnabled = annotations.annotationsAvailable && !annotations.selection.isEmpty
        if hasTarget {
            let r = m.editingRange
            refLabel.stringValue = RefLabel.text(bookName: reader.bookName(m.book), chapter: m.chapter, from: r.lowerBound, to: r.upperBound)
            passage.stringValue = passageText(book: m.book, chapter: m.chapter, range: r)
                ?? "Este versículo no existe en \(reader.translationId)."
            passage.font = ReaderFonts.reading(latin: reader.isLatin, size: 13)
            created.stringValue = m.createdAt.map { "Creada: \(DateText.dateTime($0))" } ?? ""
            modified.stringValue = (m.updatedAt != nil && m.updatedAt != m.createdAt) ? "Modificada: \(DateText.dateTime(m.updatedAt!))" : ""
            status.stringValue = m.statusText
            errorLabel.stringValue = m.errorMessage ?? ""
            errorLabel.isHidden = m.errorMessage == nil
            modeControl.selectedSegment = m.preview ? 1 : 0
            editorScroll.isHidden = m.preview
            previewScroll.isHidden = !m.preview
            if editor.string != m.draft {
                syncing = true
                editor.string = m.draft
                syncing = false
            }
            if m.preview { renderPreview() }
            newButton.isEnabled = m.selectedId != nil || !m.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            deleteButton.isEnabled = m.selectedId != nil
            rebuildList()
        }
        needsLayout = true
    }

    private func passageText(book: Int, chapter: Int, range: ClosedRange<Int>) -> String? {
        guard let repo = reader.verseRepoForUI else { return nil }
        let vs = (try? repo.verses(translationId: reader.translationId, book: book, chapter: chapter, from: range.lowerBound, to: range.upperBound)) ?? []
        guard !vs.isEmpty else { return nil }
        return CrossRefList.join(vs.sorted { $0.verse < $1.verse }.map(\.text), language: reader.language)
    }

    private func renderPreview() {
        let draft = editorModel.draft
        if draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            previewText.textStorage?.setAttributedString(NSAttributedString(string: "Nada que mostrar.", attributes: [
                .font: NSFont.systemFont(ofSize: 13), .foregroundColor: palette.textMuted]))
        } else {
            let st = MarkdownRenderer.Style(fontSize: 13, text: palette.textPrimary, muted: palette.textMuted, link: palette.accent,
                                            codeBackground: palette.surface)
            previewText.textStorage?.setAttributedString(MarkdownRenderer.render(draft, style: st))
        }
    }

    private func rebuildList() {
        let m = editorModel
        let show = m.notes.count > 1 || (m.notes.count == 1 && m.selectedId == nil)
        let notes = show ? Array(m.notes.prefix(6)) : []
        listTitle.isHidden = !show
        listTitle.stringValue = "Notas en este pasaje (\(m.notes.count))"
        while rowButtons.count > notes.count { rowButtons.removeLast().removeFromSuperview() }
        while rowButtons.count < notes.count {
            let b = NoteRowButton()
            b.isBordered = false; b.title = ""
            b.target = self; b.action = #selector(rowTapped(_:))
            addSubview(b); rowButtons.append(b)
        }
        for (i, n) in notes.enumerated() {
            let b = rowButtons[i]
            b.tag = i; b.palette = palette
            b.noteTitle = AnnotationListModel.title(of: n.body)
            b.rangeLabel = n.verseStart == n.verseEnd ? "\(n.verseStart)" : "\(n.verseStart)–\(n.verseEnd)"
            b.selectedRow = n.id == m.selectedId
            b.setAccessibilityLabel("Nota: \(b.noteTitle)\(n.id == m.selectedId ? ", seleccionada" : "")")
            b.needsDisplay = true
        }
    }

    // MARK: distribución

    override func layout() {
        super.layout()
        let w = bounds.width, pad: CGFloat = 12
        let inner = max(40, w - pad * 2)
        if !emptyTitle.isHidden {
            emptyTitle.frame = NSRect(x: pad, y: 40, width: inner, height: 20)
            let h = emptyBody.sizeThatFits(NSSize(width: inner, height: 200)).height
            emptyBody.frame = NSRect(x: pad, y: 66, width: inner, height: h)
            emptyButton.sizeToFit()
            emptyButton.frame.origin = NSPoint(x: (w - emptyButton.frame.width) / 2, y: 66 + h + 12)
            return
        }
        var y: CGFloat = 10
        refLabel.frame = NSRect(x: pad, y: y, width: inner, height: 18); y += 20
        passage.preferredMaxLayoutWidth = inner
        let ph = min(passage.sizeThatFits(NSSize(width: inner, height: 200)).height, 74)
        passage.frame = NSRect(x: pad, y: y, width: inner, height: ph); y += ph + 8
        if !listTitle.isHidden {
            listTitle.frame = NSRect(x: pad, y: y, width: inner, height: 15); y += 17
            for b in rowButtons { b.frame = NSRect(x: pad, y: y, width: inner, height: 24); y += 25 }
            y += 5
        }
        modeControl.frame = NSRect(x: pad, y: y, width: inner, height: 22); y += 30
        // pie: error, fechas, estado, botones
        var footer: CGFloat = 12 + 14 + 8 + 28 + 8
        if !errorLabel.isHidden { footer += errorLabel.sizeThatFits(NSSize(width: inner, height: 100)).height + 4 }
        if !created.stringValue.isEmpty { footer += 14 }
        if !modified.stringValue.isEmpty { footer += 14 }
        let editorH = max(90, bounds.height - y - footer)
        editorScroll.frame = NSRect(x: pad, y: y, width: inner, height: editorH)
        previewScroll.frame = editorScroll.frame
        y += editorH + 8
        if !errorLabel.isHidden {
            let eh = errorLabel.sizeThatFits(NSSize(width: inner, height: 100)).height
            errorLabel.frame = NSRect(x: pad, y: y, width: inner, height: eh); y += eh + 4
        }
        if !created.stringValue.isEmpty { created.frame = NSRect(x: pad, y: y, width: inner, height: 14); y += 14 }
        if !modified.stringValue.isEmpty { modified.frame = NSRect(x: pad, y: y, width: inner, height: 14); y += 14 }
        status.frame = NSRect(x: pad, y: y, width: inner, height: 14); y += 20
        newButton.sizeToFit(); deleteButton.sizeToFit()
        newButton.frame = NSRect(x: pad, y: y, width: max(newButton.frame.width, 90), height: 26)
        deleteButton.frame = NSRect(x: w - pad - max(deleteButton.frame.width, 80), y: y, width: max(deleteButton.frame.width, 80), height: 26)
    }

    override func resizeSubviews(withOldSize oldSize: NSSize) { super.resizeSubviews(withOldSize: oldSize); needsLayout = true }
}
