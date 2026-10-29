import AppKit
import BibliaCore
import ClassicKit

/// Iconos de la barra de acciones dibujados en código (sin SF Symbols: no existen en 10.13).
enum ActionIcons {
    static let size = NSSize(width: 18, height: 18)

    static func image(for a: VerseAction, filled: Bool = false, color: NSColor) -> NSImage {
        NSImage(size: size, flipped: true) { r in
            color.setStroke(); color.setFill()
            let lw: CGFloat = 1.4
            func stroke(_ p: NSBezierPath) { p.lineWidth = lw; p.lineCapStyle = .round; p.lineJoinStyle = .round; p.stroke() }
            switch a {
            case .copy:
                let back = NSBezierPath(roundedRect: NSRect(x: 2.5, y: 2.5, width: 9, height: 11), xRadius: 2, yRadius: 2)
                stroke(back)
                NSColor.clear.setFill()
                let front = NSBezierPath(roundedRect: NSRect(x: 6.5, y: 5.5, width: 9, height: 11), xRadius: 2, yRadius: 2)
                stroke(front)
            case .copyReference:
                let t = NSAttributedString(string: "\u{201C}\u{201D}", attributes: [
                    .font: NSFont.boldSystemFont(ofSize: 20), .foregroundColor: color])
                let s = t.size()
                t.draw(at: NSPoint(x: (r.width - s.width) / 2, y: (r.height - s.height) / 2 + 3))
            case .highlight:
                let p = NSBezierPath()
                p.move(to: NSPoint(x: 3, y: 15)); p.line(to: NSPoint(x: 4.5, y: 11)); p.line(to: NSPoint(x: 12, y: 3.5))
                p.line(to: NSPoint(x: 14.5, y: 6)); p.line(to: NSPoint(x: 7, y: 13.5)); p.close()
                stroke(p)
            case .note:
                let sq = NSBezierPath(roundedRect: NSRect(x: 2.5, y: 3.5, width: 11, height: 12), xRadius: 2, yRadius: 2)
                stroke(sq)
                let pen = NSBezierPath()
                pen.move(to: NSPoint(x: 8, y: 11)); pen.line(to: NSPoint(x: 15.5, y: 3.5))
                pen.lineWidth = 2.4; pen.lineCapStyle = .round; pen.stroke()
            case .bookmark:
                let p = NSBezierPath()
                p.move(to: NSPoint(x: 4.5, y: 2.5)); p.line(to: NSPoint(x: 13.5, y: 2.5)); p.line(to: NSPoint(x: 13.5, y: 16))
                p.line(to: NSPoint(x: 9, y: 12.2)); p.line(to: NSPoint(x: 4.5, y: 16)); p.close()
                if filled { p.fill() }
                stroke(p)
            case .crossRefs:
                let p = NSBezierPath()
                p.move(to: NSPoint(x: 3, y: 9)); p.line(to: NSPoint(x: 8, y: 9))
                p.curve(to: NSPoint(x: 14, y: 4), controlPoint1: NSPoint(x: 11, y: 9), controlPoint2: NSPoint(x: 11, y: 4))
                p.move(to: NSPoint(x: 8, y: 9))
                p.curve(to: NSPoint(x: 14, y: 14), controlPoint1: NSPoint(x: 11, y: 9), controlPoint2: NSPoint(x: 11, y: 14))
                stroke(p)
                for pt in [NSPoint(x: 14.5, y: 4), NSPoint(x: 14.5, y: 14), NSPoint(x: 3, y: 9)] {
                    NSBezierPath(ovalIn: NSRect(x: pt.x - 1.6, y: pt.y - 1.6, width: 3.2, height: 3.2)).fill()
                }
            case .compare:
                let box = NSBezierPath(roundedRect: NSRect(x: 1.5, y: 3.5, width: 15, height: 11), xRadius: 2, yRadius: 2)
                stroke(box)
                let mid = NSBezierPath(); mid.move(to: NSPoint(x: 9, y: 4)); mid.line(to: NSPoint(x: 9, y: 14)); stroke(mid)
            case .strong:
                let t = NSAttributedString(string: "abc", attributes: [
                    .font: NSFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: color,
                    .underlineStyle: NSNumber(value: NSUnderlineStyle.single.rawValue | NSUnderlineStyle.patternDot.rawValue),
                    .underlineColor: color])
                let s = t.size()
                t.draw(at: NSPoint(x: (r.width - s.width) / 2, y: (r.height - s.height) / 2))
            }
            return true
        }
    }

    static func close(color: NSColor) -> NSImage {
        NSImage(size: NSSize(width: 12, height: 12), flipped: true) { _ in
            color.setStroke()
            let p = NSBezierPath()
            p.move(to: NSPoint(x: 2.5, y: 2.5)); p.line(to: NSPoint(x: 9.5, y: 9.5))
            p.move(to: NSPoint(x: 9.5, y: 2.5)); p.line(to: NSPoint(x: 2.5, y: 9.5))
            p.lineWidth = 1.6; p.lineCapStyle = .round; p.stroke()
            return true
        }
    }
}

/// Botón de la barra: icono arriba, etiqueta debajo (o solo icono), insignia opcional.
final class BarButton: NSButton {
    var icon: NSImage?
    var label = ""
    var badge = 0
    var compact = false
    var palette = ReaderPalette.light
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        if isHighlighted {
            palette.selection.withAlphaComponent(0.7).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 6, yRadius: 6).fill()
        }
        let iconSize = icon?.size ?? .zero
        let iconY: CGFloat = compact ? (bounds.height - iconSize.height) / 2 : 5
        let ix = (bounds.width - iconSize.width) / 2
        icon?.draw(in: NSRect(x: ix, y: iconY, width: iconSize.width, height: iconSize.height), from: .zero,
                   operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        if !compact, !label.isEmpty {
            let a = NSAttributedString(string: label, attributes: [
                .font: NSFont.systemFont(ofSize: 10), .foregroundColor: palette.textSecondary])
            let s = a.size()
            a.draw(at: NSPoint(x: (bounds.width - min(s.width, bounds.width - 2)) / 2, y: iconY + iconSize.height + 4))
        }
        if badge > 0 {
            let t = NSAttributedString(string: badge > 99 ? "99+" : "\(badge)", attributes: [
                .font: NSFont.systemFont(ofSize: 9, weight: .bold), .foregroundColor: palette.pillText])
            let s = t.size()
            let w = max(14, s.width + 8)
            let rect = NSRect(x: ix + iconSize.width - 4, y: iconY - 3, width: w, height: 13)
            palette.pillBackground.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 6.5, yRadius: 6.5).fill()
            t.draw(at: NSPoint(x: rect.minX + (w - s.width) / 2, y: rect.minY + (13 - s.height) / 2))
        }
    }
    override var acceptsFirstResponder: Bool { false }
}

/// Muestra de color de resaltado.
final class SwatchButton: NSButton {
    var color = HighlightColor.yellow
    /// Muestra «todos los colores» (filtro del panel Notas): círculo vacío tachado.
    var isAll = false
    var active = false { didSet { needsDisplay = true } }
    var palette = ReaderPalette.light { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        let d: CGFloat = 20
        let r = NSRect(x: (bounds.width - d) / 2, y: (bounds.height - d) / 2, width: d, height: d)
        let c = NSBezierPath(ovalIn: r)
        if isAll {
            palette.background.setFill(); c.fill()
            let sl = NSBezierPath(); sl.move(to: NSPoint(x: r.minX + 4, y: r.maxY - 4)); sl.line(to: NSPoint(x: r.maxX - 4, y: r.minY + 4))
            sl.lineWidth = 1.3; palette.textSecondary.setStroke(); sl.stroke()
        } else {
            palette.highlight(color).setFill(); c.fill()
        }
        (active ? palette.accent : palette.textMuted).setStroke()
        c.lineWidth = active ? 2.2 : 1
        c.stroke()
        if isHighlighted { palette.textPrimary.withAlphaComponent(0.15).setFill(); c.fill() }
        if active {
            let p = NSBezierPath()
            p.move(to: NSPoint(x: r.minX + 5.5, y: r.midY + 0.5)); p.line(to: NSPoint(x: r.midX - 1, y: r.midY + 4)); p.line(to: NSPoint(x: r.maxX - 5, y: r.midY - 3.5))
            p.lineWidth = 1.7; p.lineCapStyle = .round; p.lineJoinStyle = .round
            palette.textPrimary.setStroke(); p.stroke()
        }
    }
}

/// Barra de acciones acoplada abajo del lector: Copiar · Con ref. · Anotar · Marcador · Referencias · Comparar · Strong,
/// muestras de color + Quitar + ×. Distribución según el ancho disponible (`ActionBarLayout`).
final class ActionBarView: NSView {
    var onAction: ((VerseAction) -> Void)?
    var onHighlight: ((HighlightColor) -> Void)?
    var onRemoveHighlight: (() -> Void)?
    var onClose: (() -> Void)?

    private var buttons: [VerseAction: BarButton] = [:]
    private var swatches: [HighlightColor: SwatchButton] = [:]
    private let removeButton = NSButton()
    private let closeButton = BarButton()
    private let pen = NSImageView()
    private var palette = ReaderPalette.light
    private var state = VerseMenuState(context: VerseActionContext())
    private var actions: [VerseAction] = []
    private(set) var barLayout = ActionBarLayout.oneRow
    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityLabel("Acciones del versículo")
        setAccessibilityRole(.group)
        for a in VerseAction.allCases where a != .highlight {
            let b = BarButton()
            b.isBordered = false; b.title = ""
            b.target = self; b.action = #selector(actionTapped(_:))
            b.tag = VerseAction.allCases.firstIndex(of: a) ?? 0
            buttons[a] = b
            addSubview(b)
        }
        for c in HighlightColor.allCases {
            let s = SwatchButton()
            s.isBordered = false; s.title = ""; s.color = c
            s.target = self; s.action = #selector(swatchTapped(_:))
            s.tag = HighlightColor.allCases.firstIndex(of: c) ?? 0
            s.setAccessibilityLabel(VerseMenuState.swatchAccessibility(c))
            s.toolTip = "Resaltar en \(c.displayName.lowercased())"
            swatches[c] = s
            addSubview(s)
        }
        removeButton.isBordered = false
        removeButton.target = self; removeButton.action = #selector(removeTapped)
        removeButton.setAccessibilityLabel("Quitar resaltado")
        removeButton.toolTip = "Quitar resaltado"
        addSubview(removeButton)
        closeButton.isBordered = false; closeButton.compact = true
        closeButton.target = self; closeButton.action = #selector(closeTapped)
        closeButton.setAccessibilityLabel("Cerrar barra de acciones")
        closeButton.toolTip = "Cerrar barra (Esc)"
        addSubview(closeButton)
        pen.setAccessibilityElement(false)
        addSubview(pen)
    }
    required init?(coder: NSCoder) { fatalError() }

    @objc private func actionTapped(_ b: NSButton) { onAction?(VerseAction.allCases[b.tag]) }
    @objc private func swatchTapped(_ b: NSButton) { onHighlight?(HighlightColor.allCases[b.tag]) }
    @objc private func removeTapped() { onRemoveHighlight?() }
    @objc private func closeTapped() { onClose?() }

    // MARK: contenido

    func update(state: VerseMenuState, activeColor: HighlightColor?, palette: ReaderPalette) {
        self.state = state; self.palette = palette
        actions = VerseActions.visible(state.context).filter { $0 != .highlight }
        for (a, b) in buttons {
            let shown = actions.contains(a)
            b.isHidden = !shown
            guard shown else { continue }
            let filled = a == .bookmark && state.bookmarked
            b.palette = palette
            b.icon = ActionIcons.image(for: a, filled: filled, color: filled ? palette.bookmarkMarker : palette.textPrimary)
            b.label = state.barLabel(a)
            b.badge = a == .crossRefs ? state.crossRefCount : 0
            b.isEnabled = state.isEnabled(a)
            b.alphaValue = b.isEnabled ? 1 : 0.4
            let acc = a == .crossRefs ? state.refsAccessibility : (a == .bookmark ? state.bookmarkTitle : (a == .copyReference ? "Copiar con referencia" : a.title))
            b.setAccessibilityLabel(acc)
            b.toolTip = tip(a, state)
            b.needsDisplay = true
        }
        for (c, s) in swatches {
            s.palette = palette
            s.active = activeColor == c
            s.isEnabled = state.canHighlight
            s.alphaValue = s.isEnabled ? 1 : 0.4
        }
        removeButton.isEnabled = state.canRemoveHighlight
        removeButton.attributedTitle = NSAttributedString(string: "Quitar", attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: state.canRemoveHighlight ? palette.accent : palette.textMuted])
        closeButton.palette = palette
        closeButton.icon = ActionIcons.close(color: palette.textSecondary)
        pen.image = ActionIcons.image(for: .highlight, color: palette.textSecondary)
        barLayout = ActionBarLayout.choose(width: bounds.width, actionCount: actions.count)
        needsLayout = true
        needsDisplay = true
    }

    private func tip(_ a: VerseAction, _ s: VerseMenuState) -> String {
        switch a {
        case .copy: return "Copiar (⌘C)"
        case .copyReference: return "Copiar con referencia (⌥⌘C)"
        case .note: return "Anotar (⌥⌘N)"
        case .bookmark: return s.bookmarked ? "Quitar marcador (⌘D)" : "Marcador (⌘D)"
        case .crossRefs: return "Referencias cruzadas (⌥⌘R)"
        case .compare: return "Comparar versiones"
        case .strong: return "Abrir en modo Strong"
        default: return a.title
        }
    }

    // MARK: distribución

    static let buttonHeight: CGFloat = 46, compactHeight: CGFloat = 30, swatchRowHeight: CGFloat = 30, pad: CGFloat = 6

    func preferredHeight(width: CGFloat) -> CGFloat {
        let n = VerseActions.visible(state.context).filter { $0 != .highlight }.count
        switch ActionBarLayout.choose(width: width, actionCount: n) {
        case .oneRow: return Self.pad * 2 + Self.buttonHeight
        case .twoRows: return Self.pad + Self.buttonHeight + 5 + 1 + 5 + Self.swatchRowHeight + Self.pad
        case .compact: return Self.pad + Self.compactHeight + 5 + 1 + 5 + Self.swatchRowHeight + Self.pad
        }
    }

    override func layout() {
        super.layout()
        barLayout = ActionBarLayout.choose(width: bounds.width, actionCount: actions.count)
        let compact = barLayout == .compact
        let bw = compact ? ActionBarLayout.compactButtonWidth : ActionBarLayout.buttonWidth
        let bh = compact ? Self.compactHeight : Self.buttonHeight
        let gap = ActionBarLayout.buttonSpacing
        let sideMargin = ActionBarLayout.padding / 2
        var x = sideMargin
        let rowY = Self.pad
        for a in actions {
            guard let b = buttons[a] else { continue }
            b.compact = compact
            b.frame = NSRect(x: x, y: rowY, width: bw, height: bh)
            x += bw + gap
        }
        // fila de colores
        let swH = Self.swatchRowHeight
        let swY: CGFloat
        var swX: CGFloat
        let swatchesWidth: CGFloat = 18 + 8 + 140 + 8 + 48 + 8 + 22
        if barLayout == .oneRow {
            swX = bounds.width - sideMargin - swatchesWidth
            swY = rowY + (bh - swH) / 2
        } else {
            swX = sideMargin
            swY = rowY + bh + 5 + 1 + 5
        }
        pen.frame = NSRect(x: swX, y: swY + 6, width: 18, height: 18)
        swX += 18 + 8
        for c in HighlightColor.allCases {
            swatches[c]?.frame = NSRect(x: swX, y: swY, width: 28, height: swH)
            swX += 28
        }
        swX += 8
        removeButton.frame = NSRect(x: swX, y: swY + 4, width: 48, height: swH - 8)
        swX += 48 + 8
        closeButton.frame = NSRect(x: swX, y: swY + 4, width: 22, height: swH - 8)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        palette.surface.setFill(); bounds.fill()
        palette.border.setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: 1).fill()
        if barLayout != .oneRow {
            let bh = barLayout == .compact ? Self.compactHeight : Self.buttonHeight
            NSRect(x: ActionBarLayout.padding / 2, y: Self.pad + bh + 5, width: bounds.width - ActionBarLayout.padding, height: 1).fill()
        }
    }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        needsLayout = true
    }
}
