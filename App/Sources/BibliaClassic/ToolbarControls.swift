import AppKit
import ClassicKit

/// Botón «chip» de la barra de herramientas «Códice»: icono y/o texto dibujados con la paleta del tema, fondo redondeado
/// (acento al 12 % cuando está activo). NSButton sin borde con `draw(_:)` propio: solo AppKit básico (10.13).
final class ToolbarChip: NSButton {
    enum Style { case plain, field }
    struct Part { var text: String; var font: NSFont; var color: (ReaderPalette) -> NSColor }

    var palette = ReaderPalette.light { didSet { needsDisplay = true } }
    var parts: [Part] = [] { didSet { needsDisplay = true } }
    /// Icono dibujado con un color (el chip lo pide con el color del estado).
    var iconProvider: ((NSColor) -> NSImage)?
    var chipActive = false { didSet { needsDisplay = true; setAccessibilityValue(chipActive ? "activado" : "desactivado") } }
    var chipStyle = Style.plain
    /// Con `trailing` el último texto se alinea a la derecha (pista «⌘L» de la referencia).
    var trailingLast = false
    var chevron = false
    private var inside = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        isBordered = false
        title = ""
        setButtonType(.momentaryChange)
        focusRingType = .default
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) no se usa") }

    override var isEnabled: Bool { didSet { needsDisplay = true } }

    func attributed(_ p: Part, enabled: Bool) -> NSAttributedString {
        NSAttributedString(string: p.text, attributes: [
            .font: p.font, .foregroundColor: enabled ? p.color(palette) : NSColor.disabledControlTextColor])
    }

    /// Ancho natural (icono + textos + márgenes).
    func fittingWidth(minWidth: CGFloat = 0, gap: CGFloat = 6, extra: CGFloat = 0) -> CGFloat {
        var w: CGFloat = 20 + extra
        if iconProvider != nil { w += 16 + (parts.isEmpty ? 0 : gap) }
        w += parts.reduce(0) { $0 + ceil(attributed($1, enabled: true).size().width) } + CGFloat(max(0, parts.count - 1)) * gap
        if chevron { w += 14 }
        return max(minWidth, ceil(w))
    }

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds.insetBy(dx: 0.5, dy: 2.5)
        let radius: CGFloat = 7
        let path = NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius)
        let fg: NSColor
        if chipActive && isEnabled {
            palette.accent.withAlphaComponent(0.12).setFill(); path.fill()
            fg = palette.accent
        } else if chipStyle == .field {
            palette.surface.setFill(); path.fill()
            palette.border.setStroke(); path.lineWidth = 1; path.stroke()
            fg = palette.textPrimary
        } else {
            fg = palette.textPrimary
        }
        if isHighlighted {
            (palette.isDark ? NSColor(white: 1, alpha: 0.10) : NSColor(white: 0, alpha: 0.07)).setFill(); path.fill()
        }
        var x = r.minX + 9
        let color = isEnabled ? (chipActive ? palette.accent : fg) : NSColor.disabledControlTextColor
        if let ip = iconProvider {
            let img = ip(color)
            let s = img.size
            img.draw(in: NSRect(x: x, y: r.midY - s.height / 2, width: s.width, height: s.height), from: .zero, operation: .sourceOver, fraction: 1)
            x += s.width + (parts.isEmpty ? 0 : 6)
        }
        for (i, p) in parts.enumerated() {
            var a = attributed(p, enabled: isEnabled)
            if chipActive && isEnabled { a = NSAttributedString(string: p.text, attributes: [.font: p.font, .foregroundColor: palette.accent]) }
            let sz = a.size()
            if trailingLast && i == parts.count - 1 && i > 0 {
                a.draw(at: NSPoint(x: r.maxX - 9 - sz.width, y: r.midY - sz.height / 2))
            } else {
                a.draw(at: NSPoint(x: x, y: r.midY - sz.height / 2))
                x += ceil(sz.width) + 6
            }
        }
        if chevron {
            let a = NSAttributedString(string: "\u{25BE}", attributes: [.font: NSFont.systemFont(ofSize: 10), .foregroundColor: palette.textMuted])
            a.draw(at: NSPoint(x: r.maxX - 9 - a.size().width, y: r.midY - a.size().height / 2))
        }
    }
}

enum ChipIcons {
    /// Dos columnas (vista paralela), dibujado con `color`.
    static func parallel(_ color: NSColor) -> NSImage { ParallelIcon.image(color: color) }
    /// Panel con barra lateral derecha (inspector).
    static func inspector(_ color: NSColor) -> NSImage { ToolbarIcons.inspector(color: color) }
}

/// Contenido de los popovers de la barra: «Ir a» y «Aa».
final class GotoPopoverController: NSViewController {
    let field: NSTextField
    init(field: NSTextField) { self.field = field; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("init(coder:) no se usa") }
    override func loadView() {
        let v = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 52))
        field.frame = NSRect(x: 14, y: 14, width: 252, height: 24)
        v.addSubview(field)
        view = v
    }
}

final class AaPopoverController: NSViewController {
    let themeControl = NSSegmentedControl(labels: ThemeChoice.allCases.map(\.label), trackingMode: .selectOne, target: nil, action: nil)
    let smaller = NSButton(title: "\u{2212}", target: nil, action: nil)
    let larger = NSButton(title: "+", target: nil, action: nil)
    let percent = NSTextField(labelWithString: "100 %")

    override func loadView() {
        let v = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 118))
        func label(_ t: String, y: CGFloat) {
            let l = NSTextField(labelWithString: t)
            l.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
            l.textColor = NSColor.secondaryLabelColor
            l.frame = NSRect(x: 16, y: y, width: 268, height: 14)
            v.addSubview(l)
        }
        label("TEMA", y: 94)
        themeControl.frame = NSRect(x: 16, y: 64, width: 268, height: 24)
        themeControl.setAccessibilityLabel("Tema")
        v.addSubview(themeControl)
        label("TAMAÑO", y: 42)
        smaller.bezelStyle = .rounded; larger.bezelStyle = .rounded
        smaller.frame = NSRect(x: 16, y: 10, width: 44, height: 26)
        larger.frame = NSRect(x: 240, y: 10, width: 44, height: 26)
        smaller.setAccessibilityLabel("Reducir tamaño de letra"); larger.setAccessibilityLabel("Aumentar tamaño de letra")
        smaller.toolTip = "Reducir tamaño (⌘−)"; larger.toolTip = "Aumentar tamaño (⌘+)"
        percent.alignment = .center
        percent.font = NSFont.monospacedDigitSystemFont(ofSize: 14, weight: .medium)
        percent.frame = NSRect(x: 64, y: 14, width: 172, height: 18)
        percent.setAccessibilityLabel("Tamaño de letra")
        for c in [smaller, larger, percent] as [NSView] { v.addSubview(c) }
        view = v
    }
}
