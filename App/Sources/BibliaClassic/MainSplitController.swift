import AppKit
import BibliaCore

/// Left: NSOutlineView with the 66 books (Chinese names from `book_names`). Right: read-only NSTextView.
final class MainSplitController: NSViewController, NSOutlineViewDataSource, NSOutlineViewDelegate {
    private let outline = NSOutlineView()
    private let textView = NSTextView()
    private var db: BibleDatabase?
    private var bookNames: [BookName] = []          // index = book - 1
    private var current = ChapterPosition(book: 43, chapter: 3)
    private let translationId = "CUV"

    override func loadView() {
        let split = NSSplitView()
        split.isVertical = true
        split.dividerStyle = .thin
        split.autoresizingMask = [.width, .height]

        // Sidebar
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("book"))
        col.title = "Libros"
        outline.addTableColumn(col)
        outline.outlineTableColumn = col
        outline.headerView = nil
        outline.rowHeight = 22
        outline.dataSource = self
        outline.delegate = self
        let side = NSScrollView()
        side.documentView = outline
        side.hasVerticalScroller = true
        side.autohidesScrollers = true
        side.setFrameSize(NSSize(width: 200, height: 680))

        // Reader
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.textContainerInset = NSSize(width: 28, height: 24)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.backgroundColor = NSColor.textBackgroundColor
        let reader = NSScrollView()
        reader.documentView = textView
        reader.hasVerticalScroller = true
        reader.setFrameSize(NSSize(width: 760, height: 680))

        split.addSubview(side)
        split.addSubview(reader)
        split.setHoldingPriority(NSLayoutConstraint.Priority(260), forSubviewAt: 0)
        view = split
        view.setFrameSize(NSSize(width: 960, height: 680))
        split.setPosition(210, ofDividerAt: 0)

        do {
            let d = try BibleDatabase.openBundled()
            db = d
            bookNames = try TranslationRepository(db: d).bookNames(language: "zh")
        } catch {
            textView.string = "No se pudo abrir bible.sqlite: \(error)"
        }
        outline.reloadData()
    }

    // MARK: data source (flat list)
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int { item == nil ? bookNames.count : 0 }
    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any { NSNumber(value: bookNames[index].book) }
    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool { false }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("bookCell")
        let cell: NSTableCellView
        if let c = outlineView.makeView(withIdentifier: id, owner: self) as? NSTableCellView {
            cell = c
        } else {
            cell = NSTableCellView()
            cell.identifier = id
            let tf = NSTextField(labelWithString: "")
            tf.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(tf)
            cell.textField = tf
            NSLayoutConstraint.activate([
                tf.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
                tf.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                tf.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
        }
        if let n = (item as? NSNumber)?.intValue, n >= 1, n <= bookNames.count { cell.textField?.stringValue = bookNames[n - 1].name }
        return cell
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        let row = outline.selectedRow
        guard row >= 0, row < bookNames.count else { return }
        showChapter(book: bookNames[row].book, chapter: 1)
    }

    // MARK: reader
    func showChapter(book: Int, chapter: Int) {
        guard let d = db else { return }
        current = ChapterPosition(book: book, chapter: chapter)
        let row = book - 1
        if row >= 0, row < bookNames.count, outline.selectedRow != row {
            outline.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            outline.scrollRowToVisible(row)
        }
        do {
            let repo = VerseRepository(db: d)
            let verses = try repo.chapter(translationId: translationId, book: book, chapter: chapter)
            let heads = try repo.headings(translationId: translationId, book: book, chapter: chapter)
            let display = ChapterBuilder.build(verses: verses, headings: heads, translationId: translationId)
            let name = (row >= 0 && row < bookNames.count) ? bookNames[row].name : "\(book)"
            textView.textStorage?.setAttributedString(Self.attributed(display, title: "\(name) \(chapter)"))
            textView.scrollToBeginningOfDocument(nil)
        } catch {
            textView.string = "Error: \(error)"
        }
    }

    static func attributed(_ verses: [DisplayVerse], title: String) -> NSAttributedString {
        let body = NSFont.systemFont(ofSize: 17)
        let bold = NSFont.boldSystemFont(ofSize: 18)
        let small = NSFont.systemFont(ofSize: 11)
        let para = NSMutableParagraphStyle()
        para.lineSpacing = 5
        para.paragraphSpacing = 4
        let headPara = NSMutableParagraphStyle()
        headPara.paragraphSpacingBefore = 14
        headPara.paragraphSpacing = 4
        let out = NSMutableAttributedString()
        let titlePara = NSMutableParagraphStyle(); titlePara.paragraphSpacing = 10
        out.append(NSAttributedString(string: title + "\n", attributes: [
            .font: NSFont.boldSystemFont(ofSize: 26), .foregroundColor: NSColor.labelColor, .paragraphStyle: titlePara]))
        for v in verses {
            for h in v.headings {
                out.append(NSAttributedString(string: h + "\n", attributes: [
                    .font: bold, .foregroundColor: NSColor.labelColor, .paragraphStyle: headPara]))
            }
            out.append(NSAttributedString(string: v.label, attributes: [
                .font: small, .baselineOffset: 7, .foregroundColor: NSColor.secondaryLabelColor, .paragraphStyle: para]))
            out.append(NSAttributedString(string: "\u{2009}" + v.text + " ", attributes: [
                .font: body, .foregroundColor: NSColor.labelColor, .paragraphStyle: para]))
        }
        return out
    }
}
