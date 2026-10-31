import SwiftUI
import AppKit

// Fondos con esquinas redondeadas para el texto del lector.
//
// `Text(AttributedString)` pinta `backgroundColor` como rectángulos cuadrados y SwiftUI no permite redondearlos
// (la API de dibujo por líneas, `TextRenderer`, solo existe desde macOS 15 y la app admite macOS 14). Técnica usada
// en todas las versiones: el texto se pinta tal cual (con sus enlaces `verse://`, así que el clic no cambia) pero SIN
// fondo en los tramos marcados con `RoundedBGKey`; detrás se dibuja un `Canvas` con rectángulos redondeados cuya
// geometría sale de componer una copia del texto con TextKit (mismas fuentes AppKit, mismo ancho, mismo interlineado).

struct RoundedBG: Hashable {
    var color: Color
    var radius: CGFloat
}

enum RoundedBGKey: AttributedStringKey {
    typealias Value = RoundedBG
    static let name = "biblia.roundedBackground"
}

/// Fuente AppKit equivalente a la `Font` de SwiftUI de ese tramo (para medir).
enum MirrorFontKey: AttributedStringKey {
    typealias Value = NSFont
    static let name = "biblia.mirrorFont"
}

extension AttributedString {
    /// Marca un tramo con un fondo redondeado.
    mutating func setRounded(_ bg: RoundedBG?, in range: Range<AttributedString.Index>? = nil) {
        if let range { self[range][RoundedBGKey.self] = bg } else { self[RoundedBGKey.self] = bg }
    }
    var hasRoundedBackgrounds: Bool { runs.contains { $0[RoundedBGKey.self] != nil } }
    /// Copia sin los fondos cuadrados de los tramos redondeados (se dibujan detrás).
    func strippingRoundedBackgrounds() -> AttributedString {
        var out = self
        for run in runs where run[RoundedBGKey.self] != nil { out[run.range].backgroundColor = nil }
        return out
    }
}

struct BackdropBand: Equatable { var rect: CGRect; var bg: RoundedBG }

enum RoundedBackdropLayout {
    /// Rectángulos (uno por línea y tramo) para un texto compuesto a `width`.
    static func bands(for attr: AttributedString, width: CGFloat, bodyFont: NSFont, lineSpacing: CGFloat,
                      tracking: CGFloat) -> [BackdropBand] {
        guard width > 1 else { return [] }
        let ns = NSMutableAttributedString()
        var groups: [(NSRange, RoundedBG)] = []
        var paragraph: NSParagraphStyle?
        for run in attr.runs {
            let text = String(attr[run.range].characters)
            var a: [NSAttributedString.Key: Any] = [.font: run[MirrorFontKey.self] ?? bodyFont]
            if let b = run.baselineOffset, b != 0 { a[.baselineOffset] = b }
            if tracking != 0 { a[.kern] = tracking }
            if paragraph == nil, let p = run[AttributeScopes.AppKitAttributes.ParagraphStyleAttribute.self] { paragraph = p }
            let loc = ns.length
            ns.append(NSAttributedString(string: text, attributes: a))
            if let bg = run[RoundedBGKey.self] {
                let r = NSRange(location: loc, length: ns.length - loc)
                if let last = groups.last, last.1 == bg, NSMaxRange(last.0) == loc {
                    groups[groups.count - 1].0 = NSUnionRange(last.0, r)
                } else { groups.append((r, bg)) }
            }
        }
        guard !groups.isEmpty, ns.length > 0 else { return [] }
        let ps = (paragraph?.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
        ps.lineSpacing = lineSpacing
        ps.lineBreakMode = .byWordWrapping
        ns.addAttribute(.paragraphStyle, value: ps, range: NSRange(location: 0, length: ns.length))

        let storage = NSTextStorage(attributedString: ns)
        let lm = NSLayoutManager()
        let tc = NSTextContainer(size: NSSize(width: width + 1, height: .greatestFiniteMagnitude))
        tc.lineFragmentPadding = 0
        lm.addTextContainer(tc)
        storage.addLayoutManager(lm)
        lm.ensureLayout(for: tc)

        let asc = bodyFont.ascender, desc = -bodyFont.descender
        var out: [BackdropBand] = []
        for (range, bg) in groups {
            let gr = lm.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            lm.enumerateLineFragments(forGlyphRange: gr) { lineRect, _, container, lineGlyphs, _ in
                let sub = NSIntersectionRange(gr, lineGlyphs)
                guard sub.length > 0 else { return }
                let b = lm.boundingRect(forGlyphRange: sub, in: container)
                // Línea base de la línea: la de un glifo sin desplazamiento (el número de versículo va elevado).
                var baseline = lineRect.minY + lm.location(forGlyphAt: lineGlyphs.location).y
                let ch = lm.characterIndexForGlyph(at: lineGlyphs.location)
                if let off = storage.attribute(.baselineOffset, at: ch, effectiveRange: nil) as? CGFloat { baseline += off }
                var x0 = b.minX, x1 = b.maxX
                // No incluir el espacio de salto de línea final.
                if x1 <= x0 { return }
                x0 = max(0, x0); x1 = min(width, x1)
                out.append(BackdropBand(rect: CGRect(x: x0, y: baseline - asc, width: x1 - x0, height: asc + desc), bg: bg))
            }
        }
        return out
    }
}

/// Se aplica como `.background` de un `Text` que ya ocupa todo el ancho disponible.
struct RoundedBackdrop: View {
    let attr: AttributedString
    let bodyFont: NSFont
    let lineSpacing: CGFloat
    let tracking: CGFloat
    /// Holgura alrededor del texto (pt).
    var padX: CGFloat = 1.5, padY: CGFloat = 1

    var body: some View {
        GeometryReader { geo in
            let bands = RoundedBackdropLayout.bands(for: attr, width: geo.size.width, bodyFont: bodyFont,
                                                    lineSpacing: lineSpacing, tracking: tracking)
            Canvas { ctx, _ in
                for b in bands {
                    let r = b.rect.insetBy(dx: -padX, dy: -padY)
                    ctx.fill(Path(roundedRect: r, cornerRadius: b.bg.radius, style: .continuous), with: .color(b.bg.color))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
